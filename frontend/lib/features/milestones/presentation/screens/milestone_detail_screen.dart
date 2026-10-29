import 'package:flutter/material.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../evidence/data/datasources/evidence_local_data_source.dart';
import '../../../evidence/domain/entities/evidence.dart';
import '../../../evidence/domain/geo/closeness_validator.dart';
import '../../../evidence/presentation/screens/evidence_gallery_screen.dart';
import '../../domain/entities/milestone.dart';
import '../../domain/schedule/milestone_schedule.dart';

/// Detalle Técnico del hito (CU-65, RF_02/RF_03).
///
/// CU-65 paso 2: al abrirse recupera de la BD local la **metadata** del hito
/// (ya recibida en [hito]), las **notas técnicas** y las **fotografías**
/// cargadas ([EvidenceLocalDataSource.listByHito]).
///
/// CU-65 paso 4: despliega el detalle técnico (nombre, descripción, duración,
/// estado y criticidad) junto con la galería de evidencias del hito — cada
/// tarjeta con su tipo, fecha, nota y la marca roja de "fuera de obra"
/// (CU-35) cuando corresponde. El botón "Ver galería y mapa" abre el CU-40.
///
/// Manejo de estado propio (loading / vacío / error) sin bloc nuevo: la
/// lectura es puntual y el estado vive en el [State].
class MilestoneDetailScreen extends StatefulWidget {
  /// Hito cuyo detalle técnico se muestra (metadata ya resuelta por la
  /// Línea de Tiempo / Hoja de Ruta, CU-64 paso 1).
  final Milestone hito;

  /// DAO de evidencias inyectable (tests); en producción se crea sobre la BD
  /// local real (offline-first, CU-42).
  final EvidenceLocalDataSource? evidenceDao;

  const MilestoneDetailScreen({
    super.key,
    required this.hito,
    this.evidenceDao,
  });

  /// CU-65 Alt. 2.1/2.2: mensaje exacto cuando el hito no tiene evidencia.
  static const String emptyEvidenceMessage =
      'Sin evidencia registrada para esta etapa';

  @override
  State<MilestoneDetailScreen> createState() => _MilestoneDetailScreenState();
}

class _MilestoneDetailScreenState extends State<MilestoneDetailScreen> {
  late final EvidenceLocalDataSource _evidenceDao;
  List<Evidence> _evidences = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _evidenceDao = widget.evidenceDao ??
        EvidenceLocalDataSource(localDatabase: LocalDatabase());
    _load();
  }

  /// CU-65 paso 2: lee las evidencias (fotos/videos + notas técnicas) del
  /// hito desde la BD local.
  Future<void> _load() async {
    try {
      final evidences = await _evidenceDao.listByHito(widget.hito.id);
      if (!mounted) return;
      setState(() {
        _evidences = evidences;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('CacheStorageException: ', '');
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  /// CU-40: abre la galería completa de evidencias y su mapa de relevamiento.
  void _openGallery() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EvidenceGalleryScreen(
          hitoId: widget.hito.id,
          hitoNombre: widget.hito.nombre,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'DETALLE TÉCNICO DEL HITO',
          style: TextStyle(
            fontFamily: 'Cinzel',
            color: AppTheme.accentGold,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        iconTheme: const IconThemeData(color: AppTheme.accentGold),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentGold),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.primaryRed),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGold,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final notas = [
      for (final evidence in _evidences)
        if (evidence.nota != null && evidence.nota!.trim().isNotEmpty)
          evidence.nota!.trim(),
    ];
    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        // CU-65 paso 4: metadata técnica del hito.
        _MetadataCard(hito: widget.hito),
        const SizedBox(height: 16),
        if (_evidences.isEmpty)
          _emptyEvidenceView()
        else ...[
          // CU-65 paso 2: notas técnicas recuperadas de la BD.
          if (notas.isNotEmpty) ...[
            const _SectionTitle('NOTAS TÉCNICAS'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppTheme.accentGold.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final nota in notas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.notes,
                              size: 14, color: AppTheme.lightBlue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              nota,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // CU-65 paso 4: galería de evidencias del hito.
          _SectionTitle('GALERÍA DE EVIDENCIAS (${_evidences.length})'),
          const SizedBox(height: 8),
          for (final evidence in _evidences)
            _EvidenceThumbnail(evidence: evidence),
        ],
        const SizedBox(height: 8),
        // CU-40: acceso a la galería completa con el mapa de relevamiento.
        ElevatedButton.icon(
          onPressed: _openGallery,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentGold,
            foregroundColor: Colors.black,
          ),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Ver galería y mapa'),
        ),
      ],
    );
  }

  /// CU-65 Alt. 2.1/2.2: el hito todavía no tiene evidencia cargada.
  Widget _emptyEvidenceView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: const Column(
        children: [
          Icon(Icons.no_photography_outlined, color: Colors.white24, size: 40),
          SizedBox(height: 8),
          Text(
            MilestoneDetailScreen.emptyEvidenceMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Título de sección del detalle técnico (Cinzel dorado, convención de la app).
class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Cinzel',
        color: AppTheme.accentGold,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// CU-65 paso 4: metadata del hito — nombre, descripción, duración, estado y
/// criticidad.
class _MetadataCard extends StatelessWidget {
  final Milestone hito;

  const _MetadataCard({required this.hito});

  Color _statusColor(MilestoneStatus estado) {
    switch (estado) {
      case MilestoneStatus.certificado:
        return Colors.greenAccent;
      case MilestoneStatus.enEjecucion:
        return AppTheme.lightBlue;
      case MilestoneStatus.pendiente:
        return Colors.white54;
    }
  }

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
                child: Text(
                  hito.nombre,
                  style: const TextStyle(
                    fontFamily: 'Cinzel',
                    color: AppTheme.accentGold,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (hito.esCritico)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryRed,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'CRÍTICA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hito.descripcion != null && hito.descripcion!.trim().isNotEmpty
                ? hito.descripcion!
                : 'Sin descripción técnica registrada.',
            style: TextStyle(
              color: hito.descripcion != null &&
                      hito.descripcion!.trim().isNotEmpty
                  ? Colors.white70
                  : Colors.white38,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule,
                  size: 14, color: _statusColor(hito.estado)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Duración estimada: ${hito.duracionDias} días · '
                  'Estado: ${hito.estado.label}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                hito.esCritico ? Icons.warning_amber : Icons.check_circle_outline,
                size: 14,
                color: hito.esCritico
                    ? AppTheme.primaryRed
                    : Colors.greenAccent,
              ),
              const SizedBox(width: 6),
              Text(
                hito.esCritico
                    ? 'Ruta crítica: cualquier demora retrasa la obra'
                    : 'Criticidad: fuera de la ruta crítica',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID técnico: ${hito.id}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// CU-65 paso 4: tarjeta-miniatura de evidencia con tipo, fecha, nota y la
/// marca roja de no coincidencia geográfica del CU-35 (soft-fail).
class _EvidenceThumbnail extends StatelessWidget {
  final Evidence evidence;

  const _EvidenceThumbnail({required this.evidence});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: evidence.fueraDeObra
              ? AppTheme.primaryRed.withValues(alpha: 0.7)
              : AppTheme.accentGold.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            evidence.esVideo ? Icons.videocam : Icons.photo_camera,
            color: AppTheme.accentGold,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      evidence.tipo.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      evidence.esSincronizado
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                      size: 14,
                      color: evidence.esSincronizado
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                  ],
                ),
                // CU-35 soft-fail: la captura no coincide con la obra.
                if (evidence.fueraDeObra)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryRed.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppTheme.primaryRed.withValues(alpha: 0.8)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.location_off_outlined,
                              color: AppTheme.primaryRed, size: 14),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ClosenessValidator.mismatchLabel,
                              style: TextStyle(
                                color: AppTheme.primaryRed,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (evidence.nota != null && evidence.nota!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Nota: ${evidence.nota}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    MilestoneScheduleView.format(evidence.fechaCaptura),
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
