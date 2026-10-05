import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/acta_payload.dart';
import '../domain/entities/signature_stroke.dart';
import '../../evidence/domain/entities/evidence.dart';

/// CU-56 (RF_05): motor de renderizado del acta de conformidad.
///
/// Carga la plantilla oficial (template) ConstructING e inyecta los datos
/// dinámicos del payload: datos maestros del proyecto, evidencias visuales
/// (fotos disponibles en el caché local) y las firmas dibujadas
/// vectorialmente. Retorna el archivo compilado en formato binario PDF
/// listo para ser almacenado y hasheado (CU-57/CU-59 en su turno).
class DefaultActaPdfGenerator {
  DefaultActaPdfGenerator({this.readImageBytes});

  /// Lee los bytes de la imagen local de una evidencia (gateway por
  /// plataforma). Null si el archivo no está disponible en el caché.
  final Future<List<int>?> Function(String archivo)? readImageBytes;

  /// Caja del recuadro de firma, en puntos PDF.
  static const double _firmaBoxW = 340;
  static const double _firmaBoxH = 150;

  Future<Uint8List> generate(ActaPayload payload) async {
    final doc = pw.Document();
    final visuales = await _registrosVisuales(payload.evidencias);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'ConstructING 2026 · Acta ${payload.actaId} · '
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey),
          ),
        ),
        build: (context) => _template(context, payload, visuales),
      ),
    );
    return doc.save();
  }

  /// Evidencias con imagen disponible localmente: se incrustan en el acta;
  /// las que ya liberaron el caché (sincronizadas) o los videos se listan
  /// sin imagen.
  Future<List<(Evidence, pw.ImageProvider)>> _registrosVisuales(
    List<Evidence> evidencias,
  ) async {
    final result = <(Evidence, pw.ImageProvider)>[];
    for (final evidencia in evidencias) {
      if (evidencia.esVideo) continue;
      final archivo = evidencia.archivo;
      if (archivo.trim().isEmpty) continue;
      try {
        final bytes = await readImageBytes?.call(archivo);
        if (bytes == null || bytes.isEmpty) continue;
        result.add((evidencia, pw.MemoryImage(Uint8List.fromList(bytes))));
      } catch (_) {
        // Registro visual no disponible en el caché: se lista sin imagen
        // (el acta nunca se bloquea por una foto faltante).
      }
    }
    return result;
  }

  List<pw.Widget> _template(
    pw.Context context,
    ActaPayload payload,
    List<(Evidence, pw.ImageProvider)> visuales,
  ) {
    final hito = payload.hito;
    final fecha = payload.fechaConformidad;
    final fechaText =
        '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';

    return [
      pw.Header(
        level: 0,
        text: 'ACTA DE CONFORMIDAD TÉCNICA',
      ),
      pw.Text(
        'ConstructING — Ecosistema de Gestión y Auditoría Técnica de Obras',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 12),
      _seccion('I. DATOS MAESTROS DEL PROYECTO'),
      pw.Bullet(text: 'Acta N°: ${payload.actaId}'),
      pw.Bullet(
          text: 'Obra: ${payload.obraNombre ?? "(sin nombre)"} '
              '(ID ${hito.obraId})'),
      if (payload.propietarioNombre != null)
        pw.Bullet(text: 'Propietario: ${payload.propietarioNombre}'),
      pw.Bullet(
          text: 'Hito: ${hito.nombre} (ID ${hito.id}) — '
              'duración estimada ${hito.duracionDias} días · '
              'estado al certificar: ${hito.estado.label}'
              '${hito.esCritico ? " · hito de RUTA CRÍTICA" : ""}'),
      if (hito.descripcion != null && hito.descripcion!.trim().isNotEmpty)
        pw.Bullet(text: 'Descripción técnica: ${hito.descripcion}'),
      pw.SizedBox(height: 12),

      _seccion('II. EVIDENCIAS VINCULADAS AL HITO (${payload.evidencias.length})'),
      if (payload.evidencias.isEmpty)
        pw.Text('Sin registros en la BD.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
      else ...[
        for (var i = 0; i < payload.evidencias.length; i++)
          _evidenciaRow(i + 1, payload.evidencias[i]),
      ],
      pw.SizedBox(height: 12),

      if (visuales.isNotEmpty) ...[
        _seccion('III. REGISTROS VISUALES DEL AVANCE'),
        for (final (evidencia, provider) in visuales)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 220,
                  height: 165,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Image(provider, fit: pw.BoxFit.cover),
                ),
                pw.Text(
                  '${evidencia.tipo.label} · '
                  '${_fechaText(evidencia.fechaCaptura)} · '
                  'GPS ${evidencia.latitud.toStringAsFixed(5)}, '
                  '${evidencia.longitud.toStringAsFixed(5)}',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey700),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 12),
      ],

      _seccion(
          '${visuales.isEmpty ? "III" : "IV"}. CONFORMIDAD TÉCNICA (RF_05)'),
      pw.Bullet(text: 'Firmante: ${payload.firmante}'),
      pw.Bullet(text: 'Fecha y hora de la conformidad: $fechaText'),
      pw.SizedBox(height: 6),
      pw.Container(
        width: _firmaBoxW,
        height: _firmaBoxH,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
        child: pw.CustomPaint(
          size: const PdfPoint(_firmaBoxW, _firmaBoxH),
          painter: (canvas, size) => _dibujarFirma(canvas, size, payload),
        ),
      ),
      pw.Text(
        'Firma manuscrita en pantalla del ${payload.firmante} '
        '(${payload.trazosFirma.length} trazo(s) capturado(s)). El proceso de '
        'doble firma se completa con la conformidad de la otra parte.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 12),

      _seccion(
          '${visuales.isEmpty ? "IV" : "V"}. DATOS BIOMÉTRICOS DEL TRAZO (CU-55, acoplados al acta)'),
      pw.Text(
        const JsonEncoder.withIndent('  ')
            .convert(payload.metadatos.toJson(trazos: payload.trazosFirma)),
        style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey800),
      ),
    ];
  }

  pw.Widget _seccion(String titulo) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6, top: 4),
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

  pw.Widget _evidenciaRow(int n, Evidence evidencia) {
    final fecha = evidencia.fechaCaptura;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 16, child: pw.Text('$n.')),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${evidencia.tipo.label} · ${_fechaText(fecha)} · '
                  'GPS ${evidencia.latitud.toStringAsFixed(5)}, '
                  '${evidencia.longitud.toStringAsFixed(5)} '
                  '(±${evidencia.precisionMetros.round()} m)'
                  '${evidencia.fueraDeObra ? " · CAPTURA FUERA DEL PERÍMETRO (CU-35)" : ""}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                if (evidencia.nota != null &&
                    evidencia.nota!.trim().isNotEmpty)
                  pw.Text(
                    'Nota: ${evidencia.nota}',
                    style:
                        const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fechaText(DateTime fecha) =>
      '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
      '${fecha.hour.toString().padLeft(2, '0')}:'
      '${fecha.minute.toString().padLeft(2, '0')}';

  /// Dibuja los trazos de la firma vectorialmente dentro del recuadro:
  /// normaliza el área capturada (x, y) al espacio disponible conservando
  /// el aspecto; el eje Y del PDF crece hacia arriba (se invierte).
  void _dibujarFirma(
    PdfGraphics canvas,
    PdfPoint size,
    ActaPayload payload,
  ) {
    final trazos = payload.trazosFirma;
    final m = payload.metadatos;
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
