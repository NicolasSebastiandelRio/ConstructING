import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../audit/data/audit_log_writer.dart';
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

  /// CU-59 paso 4: tabla de certificaciones de la BD local (sellado
  /// inmutable del acta). Inyectable; null = no registra el sello.
  final CertificationLocalDataSource? certificationDao;

  CertificationBloc({
    required this.milestoneDao,
    required this.evidenceDao,
    Future<Uint8List> Function(ActaPayload payload)? actaGenerator,
    this.persistActa,
    this.certificationDao,
    required this.auditLog,
    this.firmante = 'Profesional',
    this.requiereDobleFirma = false,
  })  : actaGenerator = actaGenerator ??
            DefaultActaPdfGenerator(
              readImageBytes: const LiveCaptureGateway().readBytes,
            ).generate,
        super(CertificationInitial()) {
    // CU-51 paso 2: consulta todos los registros asociados al hito y paso
    // 4: habilita el lienzo para ejecutar el CU-52 (Registrar Firma).
    on<LoadCertificationSummary>((event, emit) async {
      emit(CertificationLoading());
      try {
        final hito = await milestoneDao.getById(event.hitoId);
        if (hito == null) {
          throw Exception('El hito ya no existe en la Hoja de Ruta.');
        }
        final evidencias = await evidenceDao.listByHito(hito.id);
        CertificationAudit.logSummaryAccessed(hito: hito);
        emit(CertificationSummaryReady(hito: hito, evidencias: evidencias));
      } catch (e) {
        emit(CertificationError(message: _message(e)));
      }
    });

    // CU-52 paso 1: trazo levantado; se acumula sobre el resumen vigente.
    on<SignatureStrokeCommitted>((event, emit) async {
      final current = state;
      // Precondición CU-52: solo se firma desde el resumen a certificar.
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
    on<ClearSignaturePad>((event, emit) async {
      final current = state;
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
  static String otraParte(String firmante) =>
      firmante == 'Profesional' ? 'Propietario' : 'Profesional';

  Future<void> _onSignatureConfirmation(
    CertificationEvent event,
    Emitter<CertificationState> emit,
  ) async {
    final current = state;
    if (current is! CertificationSummaryReady) return;
    // El acta sellada no admite nuevas firmas.
    if (current is CertificationSignatureCaptured) return;

    if (current is CertificationSecondSignaturePending) {
      await _onSecondSignatureConfirmation(event, emit, pending: current);
    } else {
      await _onFirstSignatureConfirmation(event, emit, current: current);
    }
  }

  /// Valida los trazos vigentes (CU-52 paso 2) y extrae los metadatos
  /// biométricos (CU-55). Ante trazo inválido informa el rechazo y retorna
  /// null. Silencioso cuando no hay emisor disponible (etapa de segunda
  /// firma manejada por su llamada).
  Future<StrokeMetadata?> _validatedMetadatos({
    required List<SignatureStroke> strokes,
    required Milestone hito,
    Emitter<CertificationState>? emit,
  }) async {
    final check = SignatureStrokeValidator.validate(strokes: strokes);
    if (!check.allowed) {
      CertificationAudit.logSignatureRejected(hito: hito);
      emit?.call(CertificationSignatureRejected(
        message: check.reason!,
        hito: hito,
        evidencias: const [],
      ));
      return null;
    }
    return StrokeMetadataExtractor.extract(trazos: strokes);
  }

  /// Etapa 1 (CU-52): conformidad del [firmante]. Con doble firma activa,
  /// la conformidad solo queda en espera de la otra parte (CU-57): el
  /// acta aún no se compila, sella ni congela.
  Future<void> _onFirstSignatureConfirmation(
    CertificationEvent event,
    Emitter<CertificationState> emit, {
    required CertificationSummaryReady current,
  }) async {
    final metadatos = await _validatedMetadatos(
      strokes: current.strokes,
      hito: current.hito,
      emit: emit,
    );
    if (metadatos == null) return;

    final trazos = current.strokes;
    final conformidad = DateTime.now();

    if (requiereDobleFirma) {
      // CU-57 paso 2/3: la firma pericial/técnica queda congelada como
      // borrador de conformidad; el lienzo se limpia (CU-53, implícito en
      // el estado) para la firma de la otra parte.
      emit(CertificationSecondSignaturePending(
        primerFirmante: firmante,
        trazosPrimeraFirma: trazos,
        metadatosPrimeraFirma: metadatos,
        fechaPrimeraConformidad: conformidad,
        hito: current.hito,
        evidencias: current.evidencias,
      ));
      return;
    }

    final payload = ActaPayload(
      actaId: const Uuid().v4(),
      hito: current.hito,
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
      evidencias: pending.evidencias,
      trazosFirma: pending.trazosPrimeraFirma,
      metadatos: pending.metadatosPrimeraFirma,
      firmante: pending.primerFirmante,
      fechaConformidad: pending.fechaPrimeraConformidad,
      segundoFirmante: otraParte(pending.primerFirmante),
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
