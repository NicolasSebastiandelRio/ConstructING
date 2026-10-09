import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../audit/data/audit_log_writer.dart';
import '../../../../core/storage/local_database.dart';
import '../../../evidence/data/datasources/evidence_local_data_source.dart';
import '../../../evidence/domain/entities/evidence.dart';
import '../../../evidence/gateway/capture_gateway.dart';
import '../../../milestones/data/datasources/milestone_local_data_source.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../data/acta_pdf_generator.dart';
import '../../data/datasources/certification_local_data_source.dart';
import '../../domain/acta_hash.dart';
import '../../domain/acta_payload.dart';
import '../../domain/certification_audit.dart';
import '../../domain/conformidad_roles.dart';
import '../../domain/entities/signature_stroke.dart';
import '../../domain/stroke_metadata.dart';
import '../../domain/validation/signature_stroke_validator.dart';
import '../../gateway/acta_paths.dart';
import 'certification_event.dart';
import 'certification_state.dart';

/// Bloc del flujo de certificación legal (CU-51..CU-53, RF_05).
///
/// CU-51: consulta en BD los registros del hito (fechas, multimedia y
/// notas) y habilita el lienzo de firma. CU-52: acumula los trazos, valida
/// la longitud mínima al confirmar y captura la conformidad; ante trazo
/// inválido ejecuta CU-53 (limpia el lienzo), pide reintentar y bloquea la
/// confirmación.
class CertificationBloc extends Bloc<CertificationEvent, CertificationState> {
  final MilestoneLocalDataSource milestoneDao;
  final EvidenceLocalDataSource evidenceDao;

  /// CU-52 paso 2: motor de renderizado del acta (CU-56). Inyectable
  /// (tests); por defecto es el motor de producción (template oficial).
  final Future<Uint8List> Function(ActaPayload payload) actaGenerator;

  /// Guarda el acta en el caché local y devuelve la ruta (la localiza el
  /// CU-54). Inyectable (tests); null = no persiste el acta.
  final Future<String> Function({
    required Uint8List bytes,
    required String fileName,
  })? persistActa;

  /// Rol del firmante de esta conformidad (CU-52: Profesional/Propietario).
  final String firmante;

  /// CU-57 (doble firma, RF_05/RNF_C_05): el acta requerirá la conformidad
  /// colegiada de las dos partes. La primera firma queda en espera de la
  /// segunda antes del sellado (CU-59) y del congelamiento (CU-57). Los
  /// tests legacy de firma simple la inyectan en false.
  final bool requiereDobleFirma;

  /// CU-60 (RF_08): huella imborrable del firmado del acta.
  final AuditLogWriter auditLog;

  /// CU-56 paso 1 (RF_05): datos maestros del proyecto que se estampan en el
  /// acta compilada (nombre de la obra y del propietario vinculado). Null
  /// cuando el flujo no los tiene disponibles.
  final String? obraNombre;
  final String? propietarioNombre;

  /// CU-59 paso 4: tabla de certificaciones de la BD local (sellado
  /// inmutable del acta). Inyectable; null = no registra el sello.
  final CertificationLocalDataSource? certificationDao;

  /// CU-57: borradores de conformidad pendientes de segunda firma
  /// (persistencia de la primera firma). Inyectable; null = sin
  /// persistencia (la doble firma solo vale dentro de la sesión — tests).
  /// En producción la pantalla crea el DAO sobre la BD local real.
  final PendingConformidadDataSource? pendingConformidadDao;

  CertificationBloc({
    required this.milestoneDao,
    required this.evidenceDao,
    Future<Uint8List> Function(ActaPayload payload)? actaGenerator,
    this.persistActa,
    this.certificationDao,
    required this.auditLog,
    this.firmante = 'Profesional',
    this.requiereDobleFirma = false,
    this.pendingConformidadDao,
    this.obraNombre,
    this.propietarioNombre,
  })  : actaGenerator = actaGenerator ??
            DefaultActaPdfGenerator(
              readImageBytes: const LiveCaptureGateway().readBytes,
            ).generate,
        super(CertificationInitial()) {
    // CU-51 paso 2: consulta todos los registros asociados al hito y paso
    // 4: habilita el lienzo para ejecutar el CU-52 (Registrar Firma).
    // CU-57: si existe un borrador de conformidad pendiente (primera firma
    // ya registrada), restaurarlo: la OTRA parte retoma el flujo desde la
    // etapa 2 y el MISMO rol queda bloqueado (no firma dos veces).
    on<LoadCertificationSummary>((event, emit) async {
      emit(CertificationLoading());
      try {
        final hito = await milestoneDao.getById(event.hitoId);
        if (hito == null) {
          throw Exception('El hito ya no existe en la Hoja de Ruta.');
        }
        final evidencias = await evidenceDao.listByHito(hito.id);
        CertificationAudit.logSummaryAccessed(hito: hito);

        // CU-57/CU-59: el hito ya está certificado — el acta quedó sellada y
        // sus registros congelados. Reabrir el resumen NO habilita una nueva
        // firma (los datos certificados están grabados en piedra).
        if (hito.estado == MilestoneStatus.certificado) {
          emit(CertificationAlreadySealed(
            message: 'El hito ya fue certificado: su acta con doble firma '
                'quedó sellada y sus registros congelados (CU-57/CU-59).',
            hito: hito,
            evidencias: evidencias,
          ));
          return;
        }

        final pendiente = await pendingConformidadDao?.findPending(hito.id);
        if (pendiente != null) {
          if (!esPrimerFirmanteValido(pendiente.primerFirmante)) {
            // CU-57 (precondición colegiada): la conformidad colegiada nace
            // SIEMPRE de la conformidad técnica del profesional responsable.
            // Un borrador que no nació de esa firma no puede cerrarse (sería
            // un sello con una firma fabricada): se descarta y el hito
            // vuelve a requerir la primera firma del profesional.
            await pendingConformidadDao?.delete(hito.id);
            emit(CertificationFirstSignatureRequired(
              message: mensajeSinPrimeraFirma,
              hito: hito,
              evidencias: evidencias,
            ));
          } else if (pendiente.primerFirmante == firmante) {
            emit(CertificationAwaitingOtherParty(
              message:
                  'Ya registró su firma como ${pendiente.primerFirmante}. La '
                  'conformidad colegiada espera la firma de '
                  '${otraParte(pendiente.primerFirmante)}.',
              hito: hito,
              evidencias: evidencias,
            ));
          } else {
            emit(CertificationSecondSignaturePending(
              primerFirmante: pendiente.primerFirmante,
              trazosPrimeraFirma: [
                for (final trazo in pendiente.primerTrazos)
                  SignatureStroke.fromJson(trazo),
              ],
              metadatosPrimeraFirma:
                  StrokeMetadata.fromStoredJson(pendiente.primerMetadatos),
              fechaPrimeraConformidad: pendiente.primerFecha,
              hito: hito,
              evidencias: evidencias,
            ));
          }
          return;
        }

        // CU-57: sin borrador previo la PRIMERA firma corresponde al
        // profesional responsable. El Propietario que abra un hito sin la
        // conformidad técnica registrada NO puede forzar la certificación:
        // se le muestra el resumen en modo lectura, sin lienzo.
        if (!puedeAbrirConformidad) {
          emit(CertificationFirstSignatureRequired(
            message: mensajeSinPrimeraFirma,
            hito: hito,
            evidencias: evidencias,
          ));
          return;
        }

        emit(CertificationSummaryReady(hito: hito, evidencias: evidencias));
      } catch (e) {
        emit(CertificationError(message: _message(e)));
      }
    });

    // CU-52 paso 1: trazo levantado; se acumula sobre el resumen vigente.
    // CU-57: solo se acumula si el estado habilita el lienzo — un rol que ya
    // firmó, un hito sellado o un hito sin conformidad técnica previa quedan
    // bloqueados (no se degrada el estado bloqueado a uno firmable).
    on<SignatureStrokeCommitted>((event, emit) async {
      final current = state;
      if (!current.signaturePadEnabled) return;
      if (current is! CertificationSummaryReady) return;
      emit(current.copyWith(
        strokes: [
          ...current.strokes,
          SignatureStroke(List.of(event.points)),
        ],
      ));
    });

    // CU-53 paso 2: borra el buffer del lienzo; poscondición: lienzo en
    // blanco listo para una nueva captura (respuesta instantánea, RNF_U_05).
    // CU-57: solo sobre un lienzo habilitado (no reabre el acta sellada).
    on<ClearSignaturePad>((event, emit) async {
      final current = state;
      if (!current.signaturePadEnabled) return;
      if (current is! CertificationSummaryReady) return;
      emit(current.copyWith(strokes: const []));
    });

    // CU-52 paso 1/2 + CU-57: el actor presiona "Confirmar". Valida la
    // longitud del trazo (Alt. 2.1/2.2: CU-53, reintentar, bloqueo) y
    // captura la conformidad. Con doble firma, la primera confirmación
    // queda EN ESPERA de la segunda parte (conformidad colegiada) antes de
    // ejecutar CU-55 (Metadatos), CU-56 (Generar PDF), CU-57 (Congelar
    // Registros), CU-59 (Hash) y CU-60 (Audit Log).
    on<SignatureConfirmationRequested>(_onSignatureConfirmation);
  }

  /// Rol de la otra parte en la conformidad colegiada (CU-57).
  static String otraParte(String firmante) => ConformidadRoles.otraParte(firmante);

  /// CU-57 (RF_05/RNF_C_05): rol que ABRE la conformidad colegiada. El
  /// Propietario solo puede refrendar una conformidad técnica ya iniciada:
  /// la primera firma es siempre del profesional responsable.
  static const String rolPrimerFirmante = ConformidadRoles.primerFirmante;

  /// CU-57: ¿el borrador de conformidad nació de la firma técnica?
  static bool esPrimerFirmanteValido(String primerFirmante) =>
      ConformidadRoles.esPrimerFirmanteValido(primerFirmante);

  /// CU-57: mensaje único del bloqueo por falta de conformidad técnica.
  static const String mensajeSinPrimeraFirma =
      'La conformidad colegiada requiere primero la firma del profesional '
      'responsable: el hito aún no tiene su conformidad técnica registrada.';

  /// CU-57: ¿este rol puede ABRIR la conformidad (primera firma)? Con firma
  /// simple (legacy) cualquier actor firma; con conformidad colegiada, solo
  /// el profesional responsable.
  bool get puedeAbrirConformidad =>
      !requiereDobleFirma || firmante == rolPrimerFirmante;

  Future<void> _onSignatureConfirmation(
    CertificationEvent event,
    Emitter<CertificationState> emit,
  ) async {
    final current = state;
    // CU-52/CU-57: solo se firma desde un estado que habilita el lienzo. El
    // acta sellada, la espera de la otra parte y el hito sin conformidad
    // técnica previa quedan bloqueados (guards del flujo colegiado).
    if (!current.signaturePadEnabled) return;
    if (current is! CertificationSummaryReady) return;

    if (current is CertificationSecondSignaturePending) {
      // CU-57: el MISMO rol no refrenda su propia conformidad. Sin este
      // guard, una sola sesión sellaría el acta con una segunda firma
      // fabricada (firmante2 apuntaría a quien nunca firmó).
      if (current.primerFirmante == firmante) {
        emit(CertificationAwaitingOtherParty(
          message: 'Ya registró su firma como ${current.primerFirmante}. La '
              'conformidad colegiada espera la firma de '
              '${otraParte(current.primerFirmante)}.',
          hito: current.hito,
          evidencias: current.evidencias,
        ));
        return;
      }
      await _onSecondSignatureConfirmation(event, emit, pending: current);
      return;
    }

    // CU-57: la primera firma (apertura de la conformidad colegiada) es
    // potestad del profesional responsable.
    if (!puedeAbrirConformidad) {
      emit(CertificationFirstSignatureRequired(
        message: mensajeSinPrimeraFirma,
        hito: current.hito,
        evidencias: current.evidencias,
      ));
      return;
    }

    await _onFirstSignatureConfirmation(event, emit, current: current);
  }

  /// Valida los trazos vigentes (CU-52 paso 2) y extrae los metadatos
  /// biométricos (CU-55). Ante trazo inválido informa el rechazo y retorna
  /// null. Silencioso cuando no hay emisor disponible (etapa de segunda
  /// firma manejada por su llamada).
  Future<StrokeMetadata?> _validatedMetadatos({
    required List<SignatureStroke> strokes,
    required Milestone hito,
    required List<Evidence> evidencias,
    Emitter<CertificationState>? emit,
  }) async {
    final check = SignatureStrokeValidator.validate(strokes: strokes);
    if (!check.allowed) {
      CertificationAudit.logSignatureRejected(hito: hito);
      emit?.call(CertificationSignatureRejected(
        message: check.reason!,
        hito: hito,
        evidencias: evidencias,
      ));
      return null;
    }
    return StrokeMetadataExtractor.extract(trazos: strokes);
  }

  /// Etapa 1 (CU-52): conformidad del [firmante]. Con doble firma activa,
  /// la conformidad queda EN ESPERA de la otra parte (CU-57): el acta aún no
  /// se compila, sella ni congela, y esta sesión queda BLOQUEADA (el mismo
  /// rol no puede refrendar su propia firma: la segunda firma solo llega
  /// abriendo el resumen con el rol contrario).
  Future<void> _onFirstSignatureConfirmation(
    CertificationEvent event,
    Emitter<CertificationState> emit, {
    required CertificationSummaryReady current,
  }) async {
    final metadatos = await _validatedMetadatos(
      strokes: current.strokes,
      hito: current.hito,
      evidencias: current.evidencias,
      emit: emit,
    );
    if (metadatos == null) return;

    final trazos = current.strokes;
    final conformidad = DateTime.now();

    if (requiereDobleFirma) {
      // CU-57 paso 2/3: la primera firma se PERSISTE como borrador de
      // conformidad (tabla conformidades_pendientes): la otra parte — en
      // otra sesión o rol — puede retomar el flujo y cerrar el acta. El
      // lienzo de ESTA sesión queda inhabilitado (CU-53 implícito): el
      // cierre colegiado exige la conformidad efectiva de la otra parte.
      await pendingConformidadDao?.save(PendingConformidad(
        hitoId: current.hito.id,
        obraId: current.hito.obraId,
        primerFirmante: firmante,
        primerTrazos: [for (final t in trazos) t.toJson()],
        primerMetadatos: metadatos.toJson(trazos: trazos),
        primerFecha: conformidad,
        createdAt: DateTime.now(),
      ));
      emit(CertificationAwaitingOtherParty(
        message: 'Su firma como $firmante quedó registrada. La conformidad '
            'colegiada espera la firma de ${otraParte(firmante)} para sellar '
            'el acta y congelar el hito (CU-57).',
        hito: current.hito,
        evidencias: current.evidencias,
      ));
      return;
    }

    final payload = ActaPayload(
      actaId: const Uuid().v4(),
      hito: current.hito,
      // CU-56 paso 1: datos maestros del proyecto estampados en el acta.
      obraNombre: obraNombre,
      propietarioNombre: propietarioNombre,
      evidencias: current.evidencias,
      trazosFirma: trazos,
      metadatos: metadatos,
      firmante: firmante,
      fechaConformidad: conformidad,
    );
    await _generarYSellarActa(
      emit: emit,
      payload: payload,
      hito: current.hito,
      evidencias: current.evidencias,
      strokesActa: trazos,
      metadatosActa: metadatos,
    );
  }

  /// CU-57 etapa 2: la otra parte confirma su trazo; la conformidad
  /// colegiada compila el acta con ambas firmas y ejecuta el sellado.
  ///
  /// Precondición (garantizada por [_onSignatureConfirmation]): este bloque
  /// solo corre cuando [firmante] es la CONTRAPARTE del primer firmante —
  /// nunca el mismo rol que ya firmó.
  Future<void> _onSecondSignatureConfirmation(
    CertificationEvent event,
    Emitter<CertificationState> emit, {
    required CertificationSecondSignaturePending pending,
  }) async {
    // Los trazos vigentes son los de la segunda parte (el estado extiende
    // SummaryReady y conserva el buffer del lienzo).
    final strokesSecond = pending.strokes;
    final check = SignatureStrokeValidator.validate(
      strokes: strokesSecond,
    );

    if (!check.allowed) {
      // Alt. 2.1/2.2 de la segunda parte: el rechazo conserva la primera
      // firma (la conformidad sigue pendiente, NO se descarta), limpia el
      // lienzo (CU-53) y pide reintentar con aviso visible.
      CertificationAudit.logSignatureRejected(hito: pending.hito);
      emit(CertificationSecondSignaturePending(
        primerFirmante: pending.primerFirmante,
        trazosPrimeraFirma: pending.trazosPrimeraFirma,
        metadatosPrimeraFirma: pending.metadatosPrimeraFirma,
        fechaPrimeraConformidad: pending.fechaPrimeraConformidad,
        hito: pending.hito,
        evidencias: pending.evidencias,
          message: check.reason,
      ));
      return;
    }

    final payload = ActaPayload(
      actaId: const Uuid().v4(),
      hito: pending.hito,
      // CU-56 paso 1: los datos maestros viajan a la compilación colegiada.
      obraNombre: obraNombre,
      propietarioNombre: propietarioNombre,
      evidencias: pending.evidencias,
      trazosFirma: pending.trazosPrimeraFirma,
      metadatos: pending.metadatosPrimeraFirma,
      firmante: pending.primerFirmante,
      fechaConformidad: pending.fechaPrimeraConformidad,
      // CU-56/CU-57: la segunda firma la aporta ESTE actor (el rol
      // contrario al primer firmante, verificado en la precondición). No se
      // deduce: se toma del firmante efectivo de la sesión.
      segundoFirmante: firmante,
      trazosSegundaFirma: strokesSecond,
      metadatosSegundaFirma: StrokeMetadataExtractor.extract(
        trazos: strokesSecond,
      ),
      fechaSegundaConformidad: DateTime.now(),
    );
    await _generarYSellarActa(
      emit: emit,
      payload: payload,
      hito: pending.hito,
      evidencias: pending.evidencias,
      strokesActa: pending.trazosPrimeraFirma,
      metadatosActa: pending.metadatosPrimeraFirma,
      firmante2: payload.segundoFirmante,
    );
  }

  /// CU-56 + CU-57 + CU-59 + CU-60: compila el PDF consolidado, congela el
  /// hito (transacción inmutable), sella el hash en la tabla de
  /// certificaciones y deja la huella imborrable en el Audit Log.
  Future<void> _generarYSellarActa({
    required Emitter<CertificationState> emit,
    required ActaPayload payload,
    required Milestone hito,
    required List<Evidence> evidencias,
    required List<SignatureStroke> strokesActa,
    required StrokeMetadata metadatosActa,
    String? firmante2,
  }) async {
    // CU-57 (invariante de la conformidad colegiada): un acta con doble
    // firma exige DOS actores distintos. El sello nunca se emite sobre una
    // firma fabricada (el mismo rol firmando las dos veces).
    if (firmante2 != null && firmante2 == payload.firmante) {
      emit(CertificationError(
        message: 'La conformidad colegiada exige la firma de ambas partes: no '
            'se sella un acta con el mismo firmante dos veces (CU-57).',
      ));
      return;
    }
    try {
      final bytes = await actaGenerator(payload);
      final persist = persistActa;
      final actaPath = persist == null
          ? null
          : await persist(
              bytes: bytes,
              fileName: actaFileName(hito.id),
            );
      // CU-57 paso 2/4 (RF_08, RNF_C_05): congelar el hito y sus
      // registros — actualización lógica a "Certificado" en transacción
      // inmutable; los Update/Delete quedan inactivos sobre esas filas.
      final hitoCongelado = await milestoneDao.freeze(hito.id);
      // CU-59 paso 2/4 (RF_08, RNF_C_05): hash SHA-256 de la totalidad
      // del documento binario, almacenado en la tabla de certificaciones
      // de la BD — sellado lógico contra modificaciones post-firma.
      final hashSha256 = ActaHash.sha256OfBytes(bytes);
      final daoCert = certificationDao;
      if (daoCert != null) {
        await daoCert.insert(CertificationRecord(
          actaId: payload.actaId,
          hitoId: hitoCongelado.id,
          obraId: hitoCongelado.obraId,
          hashSha256: hashSha256,
          firmante: payload.firmante,
          firmante2: firmante2,
          createdAt: payload.fechaConformidad,
        ));

      }
      // CU-57: la conformidad colegiada se completó — el borrador de la
      // primera firma se descarta (el acta sellada queda en certifications).
      await pendingConformidadDao?.delete(hitoCongelado.id);
      // CU-60: huella imborrable del firmado del acta (RF_08).
      await auditLog.log(
        accion: 'acta_sellada',
        detalle: 'acta=${payload.actaId} hash=${hashSha256.toLowerCase()}'
            '${firmante2 != null ? " firmante2=$firmante2" : ""}',
        obraId: hitoCongelado.obraId,
      );
      CertificationAudit.logRecordsFrozen(hito: hitoCongelado);
      CertificationAudit.logSignatureCaptured(
        hito: hitoCongelado,
        strokes: strokesActa,
      );
      emit(CertificationSignatureCaptured(
        conformidadAt: payload.fechaConformidad,
        hito: hitoCongelado,
        evidencias: evidencias,
        strokes: strokesActa,
        metadatos: metadatosActa,
        actaPath: actaPath,
        hashSha256: hashSha256,
      ));
    } catch (e) {
      emit(CertificationError(message: _message(e)));
    }
  }

  String _message(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('CacheStorageException: ', '');
}