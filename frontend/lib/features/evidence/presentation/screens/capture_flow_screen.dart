import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../data/datasources/evidence_local_data_source.dart';
import '../../domain/entities/evidence.dart';
import '../../gateway/capture_gateway.dart';
import '../../gateway/location_gateway.dart';
import '../bloc/capture_flow_bloc.dart';

/// Flujo de captura de evidencia in situ (CU-31..CU-41, RF_03).
///
/// Pantalla modal sobre el detalle del hito: CU-31 inicializa el entorno
/// de cámara aislado (solo captura en vivo, sin galería — CU-37); CU-32
/// captura la foto de avance y CU-33 el video corto; la previsualización
/// ofrece la nota técnica (CU-39) y el descarte (CU-41) antes de confirmar
/// el guardado local (CU-42 + encolado CU-44).
class CaptureFlowScreen extends StatefulWidget {
  final Milestone hito;
  final String obraId;

  /// Coordenadas ancla de la obra (CU-15) para el guard CU-35.
  final double? obraLatitud;
  final double? obraLongitud;

  /// DAO inyectable (tests); en producción se crea sobre la BD local real.
  final EvidenceLocalDataSource? evidencesDataSource;

  /// Gateways inyectables (tests usan fakes; producción usa hardware real).
  final CaptureGateway? captureGateway;
  final LocationGateway? locationGateway;

  const CaptureFlowScreen({
    super.key,
    required this.hito,
    required this.obraId,
    this.obraLatitud,
    this.obraLongitud,
    this.evidencesDataSource,
    this.captureGateway,
    this.locationGateway,
  });

  @override
  State<CaptureFlowScreen> createState() => _CaptureFlowScreenState();
}

class _CaptureFlowScreenState extends State<CaptureFlowScreen> {
  late final EvidenceLocalDataSource _evidences;

  @override
  void initState() {
    super.initState();
    _evidences = widget.evidencesDataSource ??
        EvidenceLocalDataSource(localDatabase: LocalDatabase());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CaptureFlowBloc>(
      create: (_) => CaptureFlowBloc(
        captureGateway:
            widget.captureGateway ?? const LiveCaptureGateway(),
        locationGateway:
            widget.locationGateway ?? const GeolocatorLocationGateway(),
        evidences: _evidences,
        hito: widget.hito,
        obraId: widget.obraId,
        obraLatitud: widget.obraLatitud,
        obraLongitud: widget.obraLongitud,
      )..add(CaptureFlowInit()),
      child: const _CaptureFlowView(),
    );
  }
}

class _CaptureFlowView extends StatelessWidget {
  const _CaptureFlowView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CaptureFlowBloc, CaptureFlowState>(
      listener: (context, state) {
        if (state is CaptureFlowSaved) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: AppTheme.darkSurface,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text(
              'REGISTRAR EVIDENCIA',
              style: TextStyle(
                  fontFamily: 'Cinzel',
                  color: AppTheme.accentGold,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            iconTheme: const IconThemeData(color: AppTheme.accentGold),
          ),
          body: _body(context, state),
        );
      },
    );
  }

  Widget _body(BuildContext context, CaptureFlowState state) {
    if (state is CaptureFlowFailure) {
      return _FailureView(message: state.message);
    }
    if (state is CaptureFlowProcessing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppTheme.accentGold),
            const SizedBox(height: 16),
            Text(state.message,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }
    if (state is CaptureFlowPreview) {
      return _PreviewView(draft: state.draft);
    }
    if (state is CaptureFlowSaved) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accentGold));
    }
    // CU-31 paso 4: interfaz activa y a la escucha.
    return _ReadyView();
  }
}

/// CU-31/CU-37: entorno de cámara aislado — solo botones de captura en
/// vivo; el acceso a galería ("File Picker") no existe en esta pantalla.
class _ReadyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_camera_outlined,
              color: AppTheme.accentGold, size: 64),
          const SizedBox(height: 12),
          const Text(
            'Entorno de captura en vivo',
            style: TextStyle(
                fontFamily: 'Cinzel', color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Solo puede registrarse lo que tiene frente al lente: '
              'el acceso a la galería está bloqueado (CU-37).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 32),
          // CU-32 paso 1: obturador fotográfico.
          FilledButton.icon(
            onPressed: () =>
                context.read<CaptureFlowBloc>().add(CapturePhotoRequested()),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentGold,
                foregroundColor: Colors.black),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Capturar Foto'),
          ),
          const SizedBox(height: 12),
          // CU-33 paso 1: obturador de video corto (nativo ≤ 30 s).
          FilledButton.icon(
            onPressed: () =>
                context.read<CaptureFlowBloc>().add(RecordVideoRequested()),
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.lightBlue,
                foregroundColor: Colors.black),
            icon: const Icon(Icons.videocam_outlined),
            label: const Text('Grabar Video corto (≤ 30 s)'),
          ),
        ],
      ),
    );
  }
}

/// CU-32 paso 4 / CU-33 paso 3: previsualización con la marca pericial,
/// nota técnica (CU-39, punto de extensión) y descarte (CU-41).
class _PreviewView extends StatefulWidget {
  final EvidenceDraft draft;

  const _PreviewView({required this.draft});

  @override
  State<_PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<_PreviewView> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vista previa con la marca inalterable ya estampada (CU-36).
          if (draft.tipo == EvidenceType.foto)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                Uint8List.fromList(draft.bytes),
                fit: BoxFit.contain,
                height: 320,
              ),
            )
          else
            Container(
              height: 320,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam, color: AppTheme.accentGold, size: 64),
                  SizedBox(height: 8),
                  Text('Video capturado en vivo',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            draft.marcaTexto,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 16),
          // CU-39 punto de extensión: nota técnica descriptiva.
          TextFormField(
            controller: _noteController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Añadir nota técnica (CU-39)',
              hintText: 'Ej: Fisura menor en viga V3',
              prefixIcon: const Icon(Icons.sticky_note_2_outlined,
                  color: AppTheme.accentGold),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (value) => context
                .read<CaptureFlowBloc>()
                .add(EvidenceNoteChanged(nota: value)),
          ),
          const SizedBox(height: 24),
          // CU-32 paso 5 / CU-33 paso 3: confirmación del guardado.
          ElevatedButton(
            onPressed: () =>
                context.read<CaptureFlowBloc>().add(EvidenceSaveRequested()),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentGold),
            child: const Text('Guardar',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          // CU-41: descartar y reintentar sin dejar archivos basura.
          TextButton(
            onPressed: () =>
                context.read<CaptureFlowBloc>().add(EvidenceDiscardRequested()),
            child: const Text('Descartar',
                style: TextStyle(color: AppTheme.primaryRed)),
          ),
        ],
      ),
    );
  }
}

/// Alt. de CU-31/32/33/34/35/38: alerta visual con el mensaje exacto y
/// opción de reintentar (CU-41).
class _FailureView extends StatelessWidget {
  final String message;

  const _FailureView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                color: AppTheme.primaryRed, size: 64),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context
                  .read<CaptureFlowBloc>()
                  .add(EvidenceDiscardRequested()),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentGold),
              child: const Text('Reintentar',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

