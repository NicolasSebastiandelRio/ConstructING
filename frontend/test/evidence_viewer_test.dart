import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/evidence/domain/geo/closeness_validator.dart';
import 'package:constructing_mobile/features/evidence/presentation/screens/evidence_viewer_screen.dart';

/// PNG 1x1 válido para decodificar en widget tests.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Evidence _foto({
  String archivo = 'blob://local/foto',
  bool fueraDeObra = false,
}) =>
    Evidence(
      id: 'e1',
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.foto,
      archivo: archivo,
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 5,
      fechaCaptura: DateTime(2026, 9, 19),
      tamanoBytes: 3,
      checksum: 'ABC',
      marcaTexto: 'ConstructING · 19/09/2026',
      fueraDeObra: fueraDeObra,
    );

/// Visor de evidencias (CU-40 paso 3, Sprint 4): fuente local → nube → error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'CU-40 visor: con archivo local disponible muestra la foto (etiqueta roja si fueraDeObra)',
      (tester) async {
    final bytes = Uint8List.fromList(base64Decode(_pngBase64));
    await tester.pumpWidget(MaterialApp(
      home: EvidenceViewerScreen(
        evidence: _foto(fueraDeObra: true),
        localBytesReader: (path) async => bytes,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    // CU-35 soft-fail: etiqueta roja estampada sobre la imagen.
    expect(find.text(ClosenessValidator.mismatchLabel), findsOneWidget);
    expect(find.text('Fuente: caché local del dispositivo'), findsOneWidget);
  });

  testWidgets(
      'CU-40 visor: archivo local liberado (sincronizada) → descarga de la nube',
      (tester) async {
    final bytes = Uint8List.fromList(base64Decode(_pngBase64));
    await tester.pumpWidget(MaterialApp(
      home: EvidenceViewerScreen(
        evidence: _foto(archivo: ''), // CU-44 paso 4: caché liberado.
        remoteBytesLoader: (id) async {
          expect(id, 'e1');
          return bytes;
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Fuente: nube (binario sincronizado CU-44/CU-45)'),
        findsOneWidget);
  });

  testWidgets(
      'CU-40 visor Alt.: archivo local ilegible y nube sin la evidencia → '
      'mensaje claro (sin romper la vista)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EvidenceViewerScreen(
        evidence: _foto(),
        localBytesReader: (path) async => throw Exception('blob expirado'),
        remoteBytesLoader: (id) async => throw Exception('404'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(
      find.textContaining('No se pudo previsualizar la evidencia'),
      findsOneWidget,
    );
  });

  testWidgets(
      'CU-40 visor (video): si el video no puede inicializarse informa el fallo',
      (tester) async {
    final video = Evidence(
      id: 'v1',
      hitoId: 'h1',
      obraId: 'w1',
      tipo: EvidenceType.video,
      archivo: '/tmp/video.mp4',
      latitud: -34.6,
      longitud: -58.38,
      precisionMetros: 5,
      fechaCaptura: DateTime(2026, 9, 19),
      duracionSeg: 12,
      tamanoBytes: 3,
      checksum: 'DEF',
      marcaTexto: 'm',
    );
    await tester.pumpWidget(MaterialApp(
      home: EvidenceViewerScreen(
        evidence: video,
        localBytesReader: (path) async => Uint8List.fromList([1, 2, 3]),
        videoControllerFactory: (source, {required bool isLocalFile}) {
          expect(isLocalFile, isTrue);
          // En tests no hay canal de video: initialize() fallará.
          return VideoPlayerController.networkUrl(Uri.parse('https://x/y.mp4'));
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No se pudo reproducir el video de la evidencia.'),
        findsOneWidget);
  });
}
