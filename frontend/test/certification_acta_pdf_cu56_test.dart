import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/certification/data/acta_pdf_generator.dart';
import 'package:constructing_mobile/features/certification/domain/acta_payload.dart';
import 'package:constructing_mobile/features/certification/domain/entities/signature_stroke.dart';
import 'package:constructing_mobile/features/certification/domain/stroke_metadata.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';

/// PNG 1x1 válido: permite ejercitar la incrustación de la foto de la
/// evidencia sin depender del sistema de archivos.
final Uint8List _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// Firma sintética REALISTA: una firma a mano alzada en pantalla produce
/// cientos de puntos (el lienzo emite un punto por cada evento de
/// movimiento). [trazos] × [puntosPorTrazo] puntos en total.
List<SignatureStroke> _firmaRealista({
  int trazos = 3,
  int puntosPorTrazo = 120,
  int t0 = 0,
}) {
  final resultado = <SignatureStroke>[];
  for (var s = 0; s < trazos; s++) {
    final puntos = <SignaturePoint>[];
    for (var i = 0; i < puntosPorTrazo; i++) {
      puntos.add(SignaturePoint(
        x: 40 + i * 1.7 + s * 12,
        y: 60 + math.sin((i + s * 20) / 9) * 28,
        t: t0 + s * 400 + i * 8,
        pressure: 0.4 + (i % 5) * 0.1,
      ));
    }
    resultado.add(SignatureStroke(puntos));
  }
  return resultado;
}

Milestone _hito() => const Milestone(
      id: 'h1',
      obraId: 'w1',
      nombre: 'Cimientos',
      descripcion: 'Hormigón H21 y armadura',
      duracionDias: 5,
      estado: MilestoneStatus.enEjecucion,
    );

double _longitud(List<SignatureStroke> trazos) =>
    trazos.fold<double>(0, (s, t) => s + t.lengthPx);

ActaPayload _payload({required bool dobleFirma}) {
  final firmaPro = _firmaRealista(t0: 1000);
  final firmaOwner = _firmaRealista(t0: 9000);
  return ActaPayload(
    actaId: 'acta-colegiada-1',
    hito: _hito(),
    obraNombre: 'Torre Aurora',
    propietarioNombre: 'Ana Pérez',
    evidencias: [
      Evidence(
        id: 'e1',
        hitoId: 'h1',
        obraId: 'w1',
        tipo: EvidenceType.foto,
        archivo: 'cache/foto.jpg',
        nota: 'Vaciado terminado',
        latitud: -34.6,
        longitud: -58.4,
        precisionMetros: 5,
        fechaCaptura: DateTime(2026, 10, 8, 20, 2),
        tamanoBytes: 1024,
        checksum: 'abc',
        marcaTexto: 'ConstructING',
      ),
    ],
    trazosFirma: firmaPro,
    metadatos: StrokeMetadataExtractor.extract(trazos: firmaPro),
    firmante: 'Profesional',
    fechaConformidad: DateTime(2026, 10, 8, 20, 5),
    segundoFirmante: dobleFirma ? 'Propietario' : null,
    trazosSegundaFirma: dobleFirma ? firmaOwner : const [],
    metadatosSegundaFirma:
        dobleFirma ? StrokeMetadataExtractor.extract(trazos: firmaOwner) : null,
    fechaSegundaConformidad:
        dobleFirma ? DateTime(2026, 10, 9, 15, 40) : null,
  );
}

/// Cantidad de páginas del PDF compilado (nodo `/Pages` del catálogo).
int _paginasDe(Uint8List bytes) {
  final texto = String.fromCharCodes(bytes);
  final count = RegExp(r'/Count\s+(\d+)').firstMatch(texto);
  if (count != null) return int.parse(count.group(1)!);
  // Respaldo: contar objetos de página.
  return RegExp(r'/Type\s*/Page[^s]').allMatches(texto).length;
}

/// Genera el acta capturando la salida de `print` del paquete `pdf`.
///
/// La fuente embebida (Helvetica) solo cubre Latin-1: cuando un texto usa un
/// glifo fuera de ese rango, el paquete avisa por consola y el carácter se
/// dibuja VACÍO en el documento. En un acta legal eso es inaceptable, así que
/// los tests lo tratan como fallo.
Future<({Uint8List bytes, List<String> avisos})> _generar(
  ActaPayload payload, {
  Future<List<int>?> Function(String)? readImageBytes,
}) async {
  final avisos = <String>[];
  Uint8List? bytes;
  await runZoned(
    () async {
      bytes = await DefaultActaPdfGenerator(readImageBytes: readImageBytes)
          .generate(payload);
    },
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) => avisos.add(line),
    ),
  );
  return (bytes: bytes!, avisos: avisos);
}

/// El acta no debe depender de glifos que la fuente embebida no puede
/// dibujar: se imprimirían vacíos.
void _sinGlifosFaltantes(List<String> avisos) {
  final faltantes =
      avisos.where((a) => a.contains('Unable to find a font')).toList();
  expect(
    faltantes,
    isEmpty,
    reason: 'El acta usa caracteres que la fuente del PDF no puede dibujar '
        '(quedarían en blanco): $faltantes',
  );
}

void main() {
  group('Acta PDF CU-56 — extensión acotada del documento legal', () {
    test(
        'conformidad COLEGIADA (CU-57) con firmas realistas de cientos de '
        'puntos: el acta se compila sin PdfTooBigPageException', () async {
      final payload = _payload(dobleFirma: true);
      // Ambas firmas son de cientos de puntos: es el escenario real del
      // dispositivo (y el que rompía con el volcado completo de la matriz).
      expect(payload.metadatos.puntosCount, greaterThan(300));
      expect(payload.metadatosSegundaFirma!.puntosCount, greaterThan(300));

      final resultado =
          await _generar(payload, readImageBytes: (_) async => _png1x1);
      final bytes = resultado.bytes;

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(
        String.fromCharCodes(bytes.sublist(bytes.length - 32)),
        contains('%%EOF'),
      );
      // Acta acotada: dos firmas + foto + metadatos agregados entran en pocas
      // páginas. Antes del fix eran >20 y el render abortaba.
      expect(_paginasDe(bytes), greaterThan(0));
      expect(_paginasDe(bytes), lessThanOrEqualTo(10));
      _sinGlifosFaltantes(resultado.avisos);
    });

    test('la firma simple también se mantiene acotada', () async {
      final resultado = await _generar(
        _payload(dobleFirma: false),
        readImageBytes: (_) async => _png1x1,
      );

      expect(String.fromCharCodes(resultado.bytes.sublist(0, 5)), '%PDF-');
      expect(_paginasDe(resultado.bytes), greaterThan(0));
      expect(_paginasDe(resultado.bytes), lessThanOrEqualTo(10));
      _sinGlifosFaltantes(resultado.avisos);
    });

    test('la longitud de la firma no altera la extensión del acta', () async {
      // Dos firmas mucho más largas: el documento NO debe crecer con la
      // cantidad de puntos capturados.
      final firma = _firmaRealista(trazos: 6, puntosPorTrazo: 400);
      final payload = ActaPayload(
        actaId: 'acta-larga',
        hito: _hito(),
        evidencias: const [],
        trazosFirma: firma,
        metadatos: StrokeMetadataExtractor.extract(trazos: firma),
        firmante: 'Profesional',
        fechaConformidad: DateTime(2026, 10, 8),
        segundoFirmante: 'Propietario',
        trazosSegundaFirma: firma,
        metadatosSegundaFirma: StrokeMetadataExtractor.extract(trazos: firma),
        fechaSegundaConformidad: DateTime(2026, 10, 9),
      );
      // 4.800 puntos entre las dos firmas.
      expect(
          payload.metadatos.puntosCount +
              payload.metadatosSegundaFirma!.puntosCount,
          greaterThan(4000));
      expect(_longitud(firma), greaterThan(0));

      final resultado = await _generar(payload);
      expect(_paginasDe(resultado.bytes), lessThanOrEqualTo(10));
      _sinGlifosFaltantes(resultado.avisos);
    });
  });
}
