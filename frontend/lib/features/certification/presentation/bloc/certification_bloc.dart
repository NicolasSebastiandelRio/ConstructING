import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../audit/data/audit_log_writer.dart';
import '../../../evidence/data/datasources/evidence_local_data_source.dart';
import '../../../evidence/gateway/capture_gateway.dart';
import '../../../milestones/data/datasources/milestone_local_data_source.dart';
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

  /// CU-59 paso 4: tabla de certificaciones de la BD local (sellado
  /// inmutable del acta). Inyectable; null = no registra el sello.
  final CertificationLocalDataSource? certificationDao;

  /// CU-60 (RF_08): huella imborrable del firmado del acta. Opcional.
  final AuditLogWriter? auditLog;

  CertificationBloc({
    required this.milestoneDao,
    required this.evidenceDao,
    Future<Uint8List> Function(ActaPayload payload)? actaGenerator,
    this.persistActa,
    this.certificationDao,
    this.auditLog,
    this.firmante = 'Profesional',
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

    // CU-52 paso 1/2: el actor presiona "Confirmar". Paso 2: valida la
    // longitud del trazo; Alt. 2.1/2.2: si es inferior al mínimo, ejecuta
    // CU-53 (limpia el lienzo), pide reintentar y bloquea la confirmación.
    // Si valida: captura la conformidad ejecutando CU-55 (Metadatos) y
    // CU-56 (Generar PDF); el acta queda en el caché local lista para el
    // CU-54 (descarga) y pendiente de CU-57 (Bloquear Registros) y CU-59
    // (Hash) que se enchufarán en su turno.
    on<SignatureConfirmationRequested>((event, emit) async {
      final current = state;
      if (current is! CertificationSummaryReady) return;
      final check = SignatureStrokeValidator.validate(strokes: current.strokes);
      if (!check.allowed) {
        CertificationAudit.logSignatureRejected(hito: current.hito);
        emit(CertificationSignatureRejected(
          message: check.reason!,
          hito: current.hito,
          evidencias: current.evidencias,
        ));
        return;
      }
      try {
        final metadatos = StrokeMetadataExtractor.extract(
          trazos: current.strokes,
        );
        final payload = ActaPayload(
          actaId: const Uuid().v4(),
          hito: current.hito,
          evidencias: current.evidencias,
          trazosFirma: current.strokes,
          metadatos: metadatos,
          firmante: firmante,
          fechaConformidad: DateTime.now(),
        );
        // `this.` necesario: el parámetro del constructor (nullable) hace
        // sombra al campo dentro del cuerpo del constructor.
        final generator = this.actaGenerator;
        final bytes = await generator(payload);
        final persist = persistActa;
        final actaPath = persist == null
            ? null
            : await persist(
                bytes: bytes,
                fileName: actaFileName(current.hito.id),
              );
        // CU-57 paso 2/4 (RF_08, RNF_C_05): congelar el hito y sus
        // registros — actualización lógica a "Certificado" en transacción
        // inmutable; los Update/Delete quedan inactivos sobre esas filas.
        final hitoCongelado = await milestoneDao.freeze(current.hito.id);
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
            firmante: firmante,
            createdAt: payload.fechaConformidad,
          ));
        }
        // CU-60: huella imborrable del firmado del acta (RF_08).
        await auditLog?.log(
          accion: 'acta_sellada',
          detalle: 'acta=${payload.actaId} hash=${hashSha256.toLowerCase()}',
          obraId: hitoCongelado.obraId,
        );
        CertificationAudit.logRecordsFrozen(hito: hitoCongelado);
        CertificationAudit.logSignatureCaptured(
          hito: hitoCongelado,
          strokes: current.strokes,
        );
        emit(CertificationSignatureCaptured(
          conformidadAt: payload.fechaConformidad,
          hito: hitoCongelado,
          evidencias: current.evidencias,
          strokes: current.strokes,
          metadatos: metadatos,
          actaPath: actaPath,
          hashSha256: hashSha256,
        ));
      } catch (e) {
        emit(CertificationError(message: _message(e)));
      }
    });
  }

  String _message(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('CacheStorageException: ', '');
}
