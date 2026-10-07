import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../audit/data/audit_log_writer.dart';
import '../../../audit/data/datasources/audit_log_local_data_source.dart';
import '../../../evidence/data/datasources/evidence_local_data_source.dart';
import '../../../evidence/domain/entities/evidence.dart';
import '../../../milestones/data/datasources/milestone_local_data_source.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../data/datasources/certification_local_data_source.dart';
import '../../domain/acta_payload.dart';
import '../../gateway/acta_saver.dart';
import '../bloc/certification_bloc.dart';
import '../bloc/certification_event.dart';
import '../bloc/certification_state.dart';
import '../widgets/signature_pad.dart';

/// Pantalla de pre-certificación (CU-51, RF_05).
///
/// Paso 2: consulta en BD todos los registros asociados al hito (fechas,
/// multimedia y notas) y los despliega consolidados (paso 3). Paso 4:
/// habilita el lienzo para ejecutar el CU-52 (Registrar Firma). Es el
/// punto de ingreso tras el CU-50 (Profesional) y, más adelante, del
/// acceso del Propietario desde la notificación de solicitud de firma.
class CertificationSummaryScreen extends StatefulWidget {
  final String hitoId;

  /// Datos maestros del proyecto para el acta (CU-56, opcional).
  final String? obraNombre;

  /// Rol del firmante de esta conformidad (CU-52): "Profesional" o
  /// "Propietario" (default: Profesional).
  final String? firmante;

  /// CU-57 (doble firma, PT-07): la conformidad es colegiada — la primera
  /// firma queda en espera de la segunda parte antes del sellado. Los tests
  /// de firma simple la inyectan en false.
  final bool requiereDobleFirma;

  /// DAO inyectables (tests); en producción se crean sobre la BD local real.
  final MilestoneLocalDataSource? milestoneDao;
  final EvidenceLocalDataSource? evidenceDao;

  /// Seams de generación/persistencia del acta (CU-55/CU-56, tests).
  final Future<Uint8List> Function(ActaPayload payload)? actaGenerator;
  final Future<String> Function({
    required Uint8List bytes,
    required String fileName,
  })? persistActa;

  /// Tabla de certificaciones (CU-59); en producción se crea sobre la BD local.
  final CertificationLocalDataSource? certificationDao;

  /// CU-60: Servicio de Audit Log (inyectable en tests; producción crea el
  /// escritor sobre la BD local real).
  final AuditLogWriter? auditLog;

  const CertificationSummaryScreen({
    super.key,
    required this.hitoId,
    this.obraNombre,
    this.firmante,
    this.requiereDobleFirma = true,    this.milestoneDao,
    this.evidenceDao,
    this.actaGenerator,
    this.persistActa,
    this.certificationDao,
    this.auditLog,
  });

  @override
  State<CertificationSummaryScreen> createState() =>
      _CertificationSummaryScreenState();
}

class _CertificationSummaryScreenState
    extends State<CertificationSummaryScreen> {
  late final CertificationBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = CertificationBloc(
      milestoneDao: widget.milestoneDao ??
          MilestoneLocalDataSource(localDatabase: LocalDatabase()),
      evidenceDao: widget.evidenceDao ??
          EvidenceLocalDataSource(localDatabase: LocalDatabase()),
      firmante: widget.firmante ?? 'Profesional',
      requiereDobleFirma: widget.requiereDobleFirma,
      actaGenerator: widget.actaGenerator,
      // CU-56 paso 4: el acta compilada queda en el caché local, en la
      // convención de nombres que localiza el CU-54.
      persistActa: widget.persistActa ??
          ({required Uint8List bytes, required String fileName}) =>
              saveActaFile(bytes: bytes, fileName: fileName),
      // CU-59 paso 4: sello SHA-256 en la tabla de certificaciones local.
      certificationDao: widget.certificationDao ??
          CertificationLocalDataSource(localDatabase: LocalDatabase()),
      // CU-60: huella imborrable del firmado del acta (solo producción).
      auditLog: widget.auditLog ??
          AuditLogWriter(
            dataSource:
                AuditLogLocalDataSource(localDatabase: LocalDatabase()),
          ),
    )..add(LoadCertificationSummary(hitoId: widget.hitoId));
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CertificationBloc>.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text(
            'CERTIFICACIÓN DE ETAPA',
            style: TextStyle(
                fontFamily: 'Cinzel',
                color: AppTheme.accentGold,
                fontWeight: FontWeight.bold,
                fontSize: 15),
          ),
          iconTheme: const IconThemeData(color: AppTheme.accentGold),
        ),
        body: BlocBuilder<CertificationBloc, CertificationState>(
          builder: (context, state) {
            if (state is CertificationLoading) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.accentGold),
              );
            }
            if (state is CertificationError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.message,
                        style: const TextStyle(color: AppTheme.primaryRed),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => context.read<CertificationBloc>().add(
                            LoadCertificationSummary(hitoId: widget.hitoId),
                          ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentGold,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              );
            }
            if (state is CertificationSummaryReady) {
              return _SummaryBody(state: state);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

/// Resumen consolidado (CU-51 paso 3) + lienzo de conformidad (paso 4).
class _SummaryBody extends StatelessWidget {
  final CertificationSummaryReady state;

  const _SummaryBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final hito = state.hito;
    final captured =
        state is CertificationSignatureCaptured
            ? state as CertificationSignatureCaptured
            : null;
    final pendiente =
        state is CertificationSecondSignaturePending
            ? state as CertificationSecondSignaturePending
            : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HitoSummaryCard(hito: hito),
        const SizedBox(height: 16),
        Text(
          state.evidencias.isEmpty
              ? 'EVIDENCIAS DEL HITO · sin registros en la BD'
              : 'EVIDENCIAS DEL HITO (${state.evidencias.length})',
          style: const TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontSize: 13,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...state.evidencias.map(_EvidenceSummaryTile.new),
        const SizedBox(height: 20),
        // CU-51 paso 4 / CU-52: lienzo de conformidad técnica.
        const Text(
          'CONFORMIDAD TÉCNICA',
          style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontSize: 13,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'La firma manuscrita acredita la conformidad legal y técnica de '
          'las partes sobre el avance registrado.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 12),
        if (state is CertificationSignatureRejected)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryRed.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppTheme.primaryRed.withValues(alpha: 0.7)),
            ),
            child: Text(
              (state as CertificationSignatureRejected).message,
              style: const TextStyle(
                  color: AppTheme.primaryRed,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
        if (pendiente != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppTheme.accentGold.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CU-57 · Firma de ${pendiente.primerFirmante} registrada. '
                  'La conformidad es colegiada: falta la firma de '
                  '${CertificationBloc.otraParte(pendiente.primerFirmante)} '
                  'para sellar el acta y congelar el hito.',
                  style: TextStyle(
                      color: AppTheme.accentGold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                if (pendiente.message != null && pendiente.message!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      pendiente.message!,
                      style: const TextStyle(
                          color: AppTheme.primaryRed,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        if (captured != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Firma registrada: conformidad técnica otorgada.',
                  style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                // CU-56: acta compilada en el caché local (CU-54 la descarga).
                if (captured.actaPath != null)
                  Text(
                    'Acta de conformidad generada: lista para descargar.',
                    style: TextStyle(
                        color: Colors.greenAccent.withValues(alpha: 0.8),
                        fontSize: 11),
                  ),
                // CU-59: sello criptográfico inmutable del documento.
                Text(
                  'Sello SHA-256: ${captured.hashSha256.substring(0, 12)}…',
                  style: TextStyle(
                      color: Colors.greenAccent.withValues(alpha: 0.8),
                      fontSize: 11),
                ),
              ],
            ),
          ),
        const SignaturePad(),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Tarjeta de datos del hito (CU-51 paso 2).
class _HitoSummaryCard extends StatelessWidget {
  final Milestone hito;

  const _HitoSummaryCard({required this.hito});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(hito.nombre,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: hito.estado == MilestoneStatus.certificado
                      ? Colors.greenAccent
                      : AppTheme.lightBlue,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hito.estado.label,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (hito.descripcion != null &&
              hito.descripcion!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(hito.descripcion!,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          Text(
            'Duración estimada: ${hito.duracionDias} días',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Fila de evidencia del resumen (CU-51 paso 2: fecha, multimedia y nota).
class _EvidenceSummaryTile extends StatelessWidget {
  final Evidence evidence;

  const _EvidenceSummaryTile(this.evidence);

  @override
  Widget build(BuildContext context) {
    final fecha = evidence.fechaCaptura;
    final fechaText = '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: evidence.fueraDeObra
                ? AppTheme.primaryRed.withValues(alpha: 0.7)
                : AppTheme.accentGold.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            evidence.esVideo ? Icons.videocam : Icons.photo_camera,
            color: AppTheme.accentGold,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${evidence.tipo.label} · $fechaText',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12),
                ),
                if (evidence.nota != null &&
                    evidence.nota!.trim().isNotEmpty)
                  Text('Nota: ${evidence.nota}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11)),
                if (evidence.fueraDeObra)
                  const Text(
                    'Captura fuera del perímetro de la obra (CU-35)',
                    style: TextStyle(
                        color: AppTheme.primaryRed,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
