import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/network/connectivity_cubit.dart';
import '../../../../core/network/connectivity_monitor.dart';
import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/evidence_local_data_source.dart';
import '../../domain/entities/evidence.dart';
import '../../domain/geo/closeness_validator.dart';
import 'evidence_viewer_screen.dart';

/// Galería de evidencias del hito + Mapa de Relevamiento (CU-40, RF_07).
///
/// Muestra la dispersión geográfica del relevamiento técnico: extrae las
/// coordenadas GPS de todas las evidencias guardadas en la BD (paso 2) y
/// clava un pin por coordenada (paso 4). El ancla geográfica de la obra
/// (CU-15) se dibuja como pin distinto y sirve de referencia de centrado;
/// la cámara encuadra todos los puntos juntos. Sin conectividad para
/// descargar los tiles muestra la vista en blanco con la alerta de la spec
/// (Alt. 2.1/2.2).
class EvidenceGalleryScreen extends StatefulWidget {
  final String hitoId;
  final String hitoNombre;

  /// Ancla geográfica de la obra (CU-15): referencia del mapa y del guard
  /// CU-35. Null si la obra no tiene ancla registrada.
  final double? obraLatitud;
  final double? obraLongitud;

  /// DAO inyectable (tests); en producción se crea sobre la BD local real.
  final EvidenceLocalDataSource? dataSource;

  const EvidenceGalleryScreen({
    super.key,
    required this.hitoId,
    required this.hitoNombre,
    this.obraLatitud,
    this.obraLongitud,
    this.dataSource,
  });

  @override
  State<EvidenceGalleryScreen> createState() => _EvidenceGalleryScreenState();
}

class _EvidenceGalleryScreenState extends State<EvidenceGalleryScreen> {
  late final EvidenceLocalDataSource _dataSource;
  List<Evidence> _evidences = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ??
        EvidenceLocalDataSource(localDatabase: LocalDatabase());
    _load();
  }

  Future<void> _load() async {
    final evidences = await _dataSource.listByHito(widget.hitoId);
    if (!mounted) return;
    setState(() {
      _evidences = evidences;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'EVIDENCIAS · ${widget.hitoNombre}',
          style: const TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold,
              fontSize: 15),
        ),
        iconTheme: const IconThemeData(color: AppTheme.accentGold),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentGold))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _evidences.isEmpty
                      ? const Center(
                          child: Text(
                            'Aún no hay evidencias registradas para este hito.',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _evidences.length,
                          itemBuilder: (context, index) => _EvidenceCard(
                            evidence: _evidences[index],
                            onTap: () => _openViewer(context, _evidences[index]),
                          ),
                        ),
                ),
                // CU-40 paso 1: acceso al Mapa de Relevamiento.
                if (_evidences.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton.icon(
                      onPressed: () => _openMap(context),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentGold,
                          foregroundColor: Colors.black),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Ver Mapa'),
                    ),
                  ),
              ],
            ),
    );
  }

  void _openMap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EvidenceMapScreen(
          hitoNombre: widget.hitoNombre,
          evidences: _evidences,
          obraLatitud: widget.obraLatitud,
          obraLongitud: widget.obraLongitud,
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, Evidence evidence) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EvidenceViewerScreen(evidence: evidence),
      ),
    );
  }
}

/// Tarjeta de evidencia con sus metadatos periciales. Al tocarla se abre
/// el visor (Sprint 4: previsualización de fotos/videos).
class _EvidenceCard extends StatelessWidget {
  final Evidence evidence;
  final VoidCallback? onTap;

  const _EvidenceCard({required this.evidence, this.onTap});

  @override
  Widget build(BuildContext context) {
    final fecha = evidence.fechaCaptura;
    final fechaText = '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: evidence.fueraDeObra
                ? AppTheme.primaryRed.withValues(alpha: 0.7)
                : AppTheme.accentGold.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
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
                        Text(evidence.tipo.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
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
                        const Spacer(),
                        const Icon(Icons.chevron_right,
                            size: 18, color: Colors.white38),
                      ],
                    ),
                    // CU-35 soft-fail: etiqueta roja sobre la tarjeta cuando
                    // la ubicación de la captura no coincide con la obra.
                    if (evidence.fueraDeObra)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryRed.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  AppTheme.primaryRed.withValues(alpha: 0.8)),
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
                    if (evidence.nota != null && evidence.nota!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Nota: ${evidence.nota}',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ),
                    Text(
                      '$fechaText · Lat ${evidence.latitud.toStringAsFixed(5)}, '
                      'Lon ${evidence.longitud.toStringAsFixed(5)} '
                      '(±${evidence.precisionMetros.round()} m)',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// CU-40 paso 4: vista de mapa con "pines" en cada coordenada de evidencia.
///
/// Referencia del mapa (Sprint 4): el ancla geográfica de la obra (CU-15)
/// se dibuja como pin distinto (bandera) y la cámara encuadra obra +
/// evidencias juntas ([CameraFit.bounds]). Ya no se centra "a ciegas" en el
/// primer pin: si el GPS del dispositivo fue impreciso al capturar, el mapa
/// queda igualmente anclado a la obra.
class EvidenceMapScreen extends StatelessWidget {
  final String hitoNombre;
  final List<Evidence> evidences;
  final double? obraLatitud;
  final double? obraLongitud;

  const EvidenceMapScreen({
    super.key,
    required this.hitoNombre,
    required this.evidences,
    this.obraLatitud,
    this.obraLongitud,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkSurface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'MAPA · $hitoNombre',
          style: const TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold,
              fontWeight: FontWeight.bold,
              fontSize: 15),
        ),
        iconTheme: const IconThemeData(color: AppTheme.accentGold),
      ),
      body: Column(
        children: [
          // Alt. 2.1/2.2: sin conectividad no hay tiles de mapa disponibles.
          // Reactivo (Sprint 4): si la pantalla se abrió durante el chequeo
          // inicial del CU-43, al volver online se recupera sola (antes
          // quedaba trabada en offline hasta reabrirla).
          Expanded(
            child: BlocBuilder<ConnectivityCubit, ConnectivityStatus>(
              builder: (context, status) =>
                  status == ConnectivityStatus.online
                      ? _mapView()
                      : _offlineView(),
            ),
          ),
          _legend(),
        ],
      ),
    );
  }

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.darkSurface,
      child: Row(
        children: [
          const Icon(Icons.flag_outlined,
              color: AppTheme.lightBlue, size: 14),
          const SizedBox(width: 4),
          const Text('Ancla de la obra (CU-15)',
              style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 16),
          const Icon(Icons.camera_alt,
              color: AppTheme.accentGold, size: 14),
          const SizedBox(width: 4),
          Text('Evidencias del hito (${evidences.length})',
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _offlineView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, color: Colors.white24, size: 72),
          SizedBox(height: 12),
          Text(
            'Mapa no disponible en modo offline',
            style: TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _mapView() {
    final points = [
      for (final evidence in evidences)
        LatLng(evidence.latitud, evidence.longitud),
    ];
    // Referencia de centrado: el ancla de la obra (CU-15) si existe; si no,
    // el primer pin de evidencia.
    final center = (obraLatitud != null && obraLongitud != null)
        ? LatLng(obraLatitud!, obraLongitud!)
        : points.first;
    final allPoints = [
      ...points,
      if (obraLatitud != null && obraLongitud != null)
        LatLng(obraLatitud!, obraLongitud!),
    ];
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        // Encuadre que abarca obra + evidencias (si difieren).
        initialCameraFit: allPoints.length > 1
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(allPoints),
                padding: const EdgeInsets.fromLTRB(48, 48, 48, 48),
                maxZoom: 17,
              )
            : null,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.constructing.app',
        ),
        MarkerLayer(
          markers: [
            if (obraLatitud != null && obraLongitud != null)
              Marker(
                point: LatLng(obraLatitud!, obraLongitud!),
                width: 40,
                height: 40,
                child: const Icon(
                  Icons.flag_outlined,
                  color: AppTheme.lightBlue,
                  size: 36,
                ),
              ),
            for (final evidence in evidences)
              Marker(
                point: LatLng(evidence.latitud, evidence.longitud),
                width: 40,
                height: 40,
                child: Icon(
                  evidence.esVideo ? Icons.videocam : Icons.camera_alt,
                  color: evidence.fueraDeObra
                      ? AppTheme.primaryRed
                      : AppTheme.accentGold,
                  size: 32,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
