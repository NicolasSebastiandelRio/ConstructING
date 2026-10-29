import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/acta_payload.dart';
import '../domain/conformidad_roles.dart';
import '../domain/entities/signature_stroke.dart';
import '../domain/stroke_metadata.dart';
import '../../evidence/domain/entities/evidence.dart';

/// CU-56/CU-57: resuelve el nombre completo de un firmante según su rol.
///
/// - Propietario: prefiere el nombre del propietario de la obra (el dato
///   maestro más fiel); si no hay, usa el nombre capturado en su sesión.
/// - Profesional: usa el nombre del nombre de la sesión que abrió la
///   conformidad.
/// Retorna null cuando no hay ningún nombre disponible.
String? nombreDelFirmante(
  String rol,
  String? nombreSesion,
  String? propietarioNombre,
) {
  if (rol == ConformidadRoles.propietario) {
    final prop = propietarioNombre?.trim();
    if (prop != null && prop.isNotEmpty) return prop;
  }
  final s = nombreSesion?.trim();
  return (s != null && s.isNotEmpty) ? s : null;
}

/// CU-56 (RF_05): motor de renderizado del acta de conformidad.
///
/// El acta está pensada para el **Propietario**: un documento corto y legible
/// con lo que le importa —qué obra y qué hito se certifican, quiénes firman,
/// cuándo y qué fotos respaldan el avance—. Los identificadores internos, los
/// hashes y la matriz biométrica NO se imprimen: siguen guardados en el
/// registro digital sellado (CU-58/CU-59) pero no ensucian el documento.
class DefaultActaPdfGenerator {
  DefaultActaPdfGenerator({this.readImageBytes});

  /// Lee los bytes de la imagen local de una evidencia (gateway por
  /// plataforma). Null si el archivo no está disponible en el caché.
  final Future<List<int>?> Function(String archivo)? readImageBytes;

  /// Ruta del logo institucional declarado en `pubspec.yaml`.
  static const String logoAsset = 'assets/images/logo.png';

  /// Caja del recuadro de firma, en puntos PDF.
  ///
  /// El ancho útil de la caja de contenido es A4 (595.28 pt) menos los
  /// márgenes horizontales de [generate] (40 + 40) = 515.28 pt.
  static const double _firmaBoxW = 340;

  /// Recuadro de firma en la conformidad COLEGIADA (CU-57): las dos firmas
  /// van lado a lado, así que cada caja mide
  /// `(515.28 − 24 de separación) / 2 = 245.6`. Con el ancho individual
  /// (340 pt) las dos cajas sumaban 704 pt sobre 515 pt útiles: el `Row`
  /// desbordaba y `MultiPage` no lograba cerrar el documento
  /// (`PdfTooBigPageException`).
  static const double _firmaBoxWDoble = 245;
  static const double _firmaGap = 24;
  static const double _firmaBoxH = 140;

  /// Máximo de fotografías que se incluyen en el acta (las más recientes se
  /// listan primero): un acta breve no debe convertirse en un álbum.
  static const int maxFotos = 4;

  Future<Uint8List> generate(ActaPayload payload) async {
    final doc = pw.Document();
    final logo = await _loadLogo();
    final visuales = await _registrosVisuales(payload.evidencias);
    final fechaDocumento =
        payload.fechaSegundaConformidad ?? payload.fechaConformidad;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'ConstructING · ${_fechaCorta(fechaDocumento)} · '
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (context) =>
            _template(context, payload, visuales, logo, fechaDocumento),
      ),
    );
    return doc.save();
  }

  /// Logo institucional. Si el asset no está disponible (por ejemplo en un
  /// test sin bundle) el acta se genera igual, sin logo.
  Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final data = await rootBundle.load(logoAsset);
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  /// Evidencias con imagen disponible localmente: se incrustan en el acta;
  /// las que ya liberaron el caché (sincronizadas) o los videos se omiten.
  Future<List<(Evidence, pw.ImageProvider)>> _registrosVisuales(
    List<Evidence> evidencias,
  ) async {
    final result = <(Evidence, pw.ImageProvider)>[];
    for (final evidencia in evidencias) {
      if (result.length >= maxFotos) break;
      if (evidencia.esVideo) continue;
      final archivo = evidencia.archivo;
      if (archivo.trim().isEmpty) continue;
      try {
        final bytes = await readImageBytes?.call(archivo);
        if (bytes == null || bytes.isEmpty) continue;
        result.add((evidencia, pw.MemoryImage(Uint8List.fromList(bytes))));
      } catch (_) {
        // Registro visual no disponible en el caché: el acta nunca se
        // bloquea por una foto faltante.
      }
    }
    return result;
  }

  List<pw.Widget> _template(
    pw.Context context,
    ActaPayload payload,
    List<(Evidence, pw.ImageProvider)> visuales,
    pw.MemoryImage? logo,
    DateTime fechaDocumento,
  ) {
    final hito = payload.hito;
    final propietario = payload.propietarioNombre?.trim();
    final profesional = nombreDelFirmante(
      ConformidadRoles.profesional,
      payload.nombreFirmante,
      null,
    );

    return [
      _encabezado(logo, fechaDocumento),
      pw.SizedBox(height: 14),

      _seccion('DATOS DE LA OBRA'),
      if (payload.obraNombre != null && payload.obraNombre!.trim().isNotEmpty)
        _dato('Obra', payload.obraNombre!.trim()),
      _dato('Hito certificado', hito.nombre),
      if (hito.descripcion != null && hito.descripcion!.trim().isNotEmpty)
        _dato('Descripción', hito.descripcion!.trim()),
      if (propietario != null && propietario.isNotEmpty)
        _dato('Propietario', propietario),
      if (profesional != null) _dato('Profesional responsable', profesional),
      _dato('Fecha de conformidad', _fechaText(fechaDocumento)),
      pw.SizedBox(height: 14),

      if (visuales.isNotEmpty) ...[
        _seccion('REGISTRO FOTOGRÁFICO'),
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (evidencia, provider) in visuales)
              _foto(evidencia, provider),
          ],
        ),
        pw.SizedBox(height: 14),
      ],

      _seccion('FIRMAS'),
      // CU-57 (doble firma): conformidad colegiada — ambas partes firman el
      // mismo documento antes del sellado criptográfico (CU-59).
      payload.conDobleFirma
          ? pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _firmaBox(
                  width: _firmaBoxWDoble,
                  titulo: payload.firmante,
                  nombreCompleto: nombreDelFirmante(
                    payload.firmante,
                    payload.nombreFirmante,
                    payload.propietarioNombre,
                  ),
                  trazos: payload.trazosFirma,
                  metadatos: payload.metadatos,
                  fecha: payload.fechaConformidad,
                ),
                pw.SizedBox(width: _firmaGap),
                _firmaBox(
                  width: _firmaBoxWDoble,
                  titulo: payload.segundoFirmante!,
                  nombreCompleto: nombreDelFirmante(
                    payload.segundoFirmante!,
                    payload.nombreSegundoFirmante,
                    payload.propietarioNombre,
                  ),
                  trazos: payload.trazosSegundaFirma,
                  metadatos: payload.metadatosSegundaFirma!,
                  fecha: payload.fechaSegundaConformidad!,
                ),
              ],
            )
          : _firmaBox(
              titulo: payload.firmante,
              nombreCompleto: nombreDelFirmante(
                payload.firmante,
                payload.nombreFirmante,
                payload.propietarioNombre,
              ),
              trazos: payload.trazosFirma,
              metadatos: payload.metadatos,
              fecha: payload.fechaConformidad,
              altoExtra: 80,
            ),
      pw.SizedBox(height: 10),
      pw.Text(
        payload.conDobleFirma
            ? 'Las dos partes otorgan su conformidad sobre el avance '
                'registrado en esta acta. La evidencia y las firmas quedan '
                'resguardadas digitalmente.'
            : 'El profesional responsable otorga su conformidad sobre el '
                'avance registrado en esta acta.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    ];
  }

  /// Encabezado institucional: logo + nombre de la app + fecha.
  pw.Widget _encabezado(pw.MemoryImage? logo, DateTime fechaDocumento) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Container(
                width: 46,
                height: 46,
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
              pw.SizedBox(width: 12),
            ],
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ConstructING',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.brown900,
                  ),
                ),
                pw.Text(
                  'Acta de Conformidad Técnica',
                  style: const pw.TextStyle(
                      fontSize: 11, color: PdfColors.grey800),
                ),
                pw.Text(
                  'Emitida el ${_fechaText(fechaDocumento)}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 1, color: PdfColors.brown900),
      ],
    );
  }

  /// Fila etiqueta/valor de los datos de la obra.
  pw.Widget _dato(String etiqueta, String valor) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 130,
              child: pw.Text(
                '$etiqueta:',
                style: const pw.TextStyle(
                    fontSize: 9.5, color: PdfColors.grey700),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                valor,
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      );

  /// Fotografía del avance con su rótulo simple (sin GPS ni identificadores).
  pw.Widget _foto(Evidence evidencia, pw.ImageProvider provider) {
    final nota = evidencia.nota?.trim();
    return pw.Container(
      width: 250,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            height: 165,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Image(provider, fit: pw.BoxFit.cover),
          ),
          pw.Text(
            '${evidencia.tipo.label} · ${_fechaCorta(evidencia.fechaCaptura)}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
          if (nota != null && nota.isNotEmpty)
            pw.Text(
              nota,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
        ],
      ),
    );
  }

  /// Recuadro de una firma manuscrita con su rótulo, nombre completo y fecha
  /// (CU-56/CU-57: "Nombre Apellido" bajo la firma, junto a la fecha).
  ///
  /// [width] es el ancho del recuadro: 340 pt en firma simple y 245 pt en la
  /// conformidad colegiada, donde las dos firmas comparten el ancho útil.
  pw.Widget _firmaBox({
    required String titulo,
    required String? nombreCompleto,
    required List<SignatureStroke> trazos,
    required StrokeMetadata metadatos,
    required DateTime fecha,
    double width = _firmaBoxW,
    double altoExtra = 0,
  }) {
    final w = width;
    final h = _firmaBoxH + altoExtra;
    final nombre = nombreCompleto?.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: w,
          height: h,
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400)),
          child: pw.CustomPaint(
            size: PdfPoint(w, h),
            painter: (canvas, size) => _dibujarTrazos(
              canvas,
              size,
              trazos: trazos,
              metadatos: metadatos,
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        // Línea 1: rol + fecha de firma.
        pw.Text(
          '$titulo · ${_fechaText(fecha)}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        // Línea 2 (CU-56): nombre completo del firmante, bajo su firma.
        if (nombre != null && nombre.isNotEmpty)
          pw.Text(
            nombre,
            style: const pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.brown900,
            ),
          ),
      ],
    );
  }

  pw.Widget _seccion(String titulo) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              titulo,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.brown900,
              ),
            ),
            pw.Divider(height: 2, thickness: 0.5, color: PdfColors.grey400),
          ],
        ),
      );

  /// Fecha y hora (DD/MM/AAAA HH:MM).
  String _fechaText(DateTime fecha) =>
      '${_fechaCorta(fecha)} '
      '${fecha.hour.toString().padLeft(2, '0')}:'
      '${fecha.minute.toString().padLeft(2, '0')}';

  /// Solo fecha (DD/MM/AAAA).
  String _fechaCorta(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';

  /// Dibuja un conjunto de trazos de firma vectorialmente dentro del
  /// recuadro: normaliza el área capturada (x, y) al espacio disponible
  /// conservando el aspecto; el eje Y del PDF crece hacia arriba.
  void _dibujarTrazos(
    PdfGraphics canvas,
    PdfPoint size, {
    required List<SignatureStroke> trazos,
    required StrokeMetadata metadatos,
  }) {
    final m = metadatos;
    if (trazos.isEmpty) return;
    final anchoArea = (m.maxX - m.minX).abs();
    final altoArea = (m.maxY - m.minY).abs();
    final margen = 12.0;
    final disponibleW = (size.x - margen * 2).clamp(1.0, double.infinity);
    final disponibleH = (size.y - margen * 2).clamp(1.0, double.infinity);
    final escala = anchoArea <= 0 && altoArea <= 0
        ? 1.0
        : 1.0 /
            ([
              anchoArea / disponibleW,
              altoArea / disponibleH,
              0.0,
            ].reduce((a, b) => a > b ? a : b));
    canvas
      ..setStrokeColor(PdfColors.black)
      ..setLineWidth(2)
      ..setLineJoin(PdfLineJoin.round);
    for (final trazo in trazos) {
      for (var i = 0; i < trazo.points.length; i++) {
        final p = trazo.points[i];
        final x = margen + (p.x - m.minX) * escala;
        final y = margen + (m.maxY - p.y) * escala;
        if (i == 0) {
          canvas.moveTo(x, y);
        } else {
          canvas.lineTo(x, y);
        }
      }
      canvas.strokePath();
    }
  }
}
