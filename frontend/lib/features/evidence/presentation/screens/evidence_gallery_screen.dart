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

/// Galería de evidencias del hito + Mapa de Relevamiento (CU-40, RF_07).
///
/// Muestra la dispersión geográfica del relevamiento técnico: extrae las
/// coordenadas GPS de todas las evidencias guardadas en la BD (paso 2) y
/// clava un pin por coordenada (paso 4). Sin conectividad para descargar
/// los tiles muestra la vista en blanco con la alerta de la spec
/// (Alt. 2.1/2.2).
class EvidenceGalleryScreen extends StatefulWidget {
  final String hitoId;
  final String hitoNombre;

  /// DAO inyectable (tests); en producción se crea sobre la BD local real.
  final EvidenceLocalDataSource? dataSource;

  const EvidenceGalleryScreen({
    super.key,
    required this.hitoId,
    required this.hitoNombre,
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
                          padding: const EdgeInsets.all(16),
                          itemCount: _evidences.length,
                          itemBuilder: (context, index) =>
                              _EvidenceCard(evidence: _evidences[index]),
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
        ),
      ),
    );
  }
}

/// Tarjeta de evidencia con sus metadatos periciales.
class _EvidenceCard extends StatelessWidget {
  final Evidence evidence;

  const _EvidenceCard({required this.evidence});

  @override
  Widget build(BuildContext context) {
    final fecha = evidence.fechaCaptura;
    final fechaText = '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.3)),
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
                  ],
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
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CU-40 paso 4: vista de mapa con "pines" en cada coordenada de evidencia.
class EvidenceMapScreen extends StatelessWidget {
  final String hitoNombre;
  final List<Evidence> evidences;

  const EvidenceMapScreen({
    super.key,
    required this.hitoNombre,
    required this.evidences,
  });

  @override
  Widget build(BuildContext context) {
    // Alt. 2.1/2.2: sin conectividad no hay tiles de mapa disponibles.
    final online =
        context.read<ConnectivityCubit>().state == ConnectivityStatus.online;
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
      body: !online
          ? _offlineView()
          : _mapView(),
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
    final center = points.first;
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.constructing.app',
        ),
        MarkerLayer(
          markers: [
            for (final evidence in evidences)
              Marker(
                point: LatLng(evidence.latitud, evidence.longitud),
                width: 40,
                height: 40,
                child: Icon(
                  evidence.esVideo ? Icons.videocam : Icons.camera_alt,
                  color: AppTheme.accentGold,
                  size: 32,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
