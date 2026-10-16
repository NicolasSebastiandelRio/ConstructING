import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/evidence/data/datasources/evidence_local_data_source.dart';
import 'package:constructing_mobile/features/evidence/domain/entities/evidence.dart';
import 'package:constructing_mobile/features/evidence/domain/geo/closeness_validator.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/screens/milestone_detail_screen.dart';

/// DAO de evidencias fake: hereda la firma del DAO real y anula solo la
/// lectura, de modo que el widget test nunca abre la BD real.
class _FakeEvidenceDao extends EvidenceLocalDataSource {
  _FakeEvidenceDao([List<Evidence> evidences = const []])
      : _evidences = evidences,
        super(localDatabase: LocalDatabase());

  final List<Evidence> _evidences;

  @override
  Future<List<Evidence>> listByHito(String hitoId) async =>
      _evidences.where((e) => e.hitoId == hitoId).toList();
}

Evidence _evidencia({
  String id = 'e1',
  String hitoId = 'h1',
  EvidenceType tipo = EvidenceType.foto,
  String? nota,
  bool fueraDeObra = false,
}) {
  return Evidence(
    id: id,
    hitoId: hitoId,
    obraId: 'w1',
    tipo: tipo,
    archivo: 'cache/foto.jpg',
    nota: nota,
    latitud: -34.6,
    longitud: -58.4,
    precisionMetros: 5,
    fechaCaptura: DateTime(2026, 9, 1, 10),
    tamanoBytes: 1024,
    checksum: 'checksum-e1',
    marcaTexto: 'ConstructING',
    fueraDeObra: fueraDeObra,
  );
}

const _hito = Milestone(
  id: 'h1',
  obraId: 'w1',
  nombre: 'Cimientos',
  descripcion: 'Hormigonado de bases y plateas',
  duracionDias: 5,
  esCritico: true,
);

Future<void> _pumpDetail(
  WidgetTester tester, {
  required _FakeEvidenceDao dao,
  Milestone hito = _hito,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MilestoneDetailScreen(hito: hito, evidenceDao: dao),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CU-65 Detalle Técnico del hito', () {
    testWidgets('muestra el nombre, la descripción y las notas técnicas '
        'recuperadas de la BD', (tester) async {
      final dao = _FakeEvidenceDao([
        _evidencia(nota: 'Hormigón H-21 con ensayo de probeta'),
      ]);

      await _pumpDetail(tester, dao: dao);

      expect(find.text('DETALLE TÉCNICO DEL HITO'), findsOneWidget);
      expect(find.text('Cimientos'), findsOneWidget);
      expect(find.text('Hormigonado de bases y plateas'), findsOneWidget);
      expect(find.text('NOTAS TÉCNICAS'), findsOneWidget);
      expect(
        find.text('Hormigón H-21 con ensayo de probeta'),
        findsOneWidget,
      );
      // Metadata del hito: duración, estado y criticidad.
      expect(find.textContaining('Duración estimada: 5 días'), findsOneWidget);
      expect(find.textContaining('Estado: Pendiente'), findsOneWidget);
      expect(find.text('CRÍTICA'), findsOneWidget);
    });

    testWidgets('con evidencias seeded muestra las tarjetas de la galería '
        'con tipo, fecha, nota y marca fuera de obra (CU-35)',
        (tester) async {
      final dao = _FakeEvidenceDao([
        _evidencia(nota: 'Base este'),
        _evidencia(
          id: 'e2',
          tipo: EvidenceType.video,
          fueraDeObra: true,
        ),
      ]);

      await _pumpDetail(tester, dao: dao);

      expect(find.text('GALERÍA DE EVIDENCIAS (2)'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);
      expect(find.text('Nota: Base este'), findsOneWidget);
      expect(find.text('01/09/2026'), findsNWidgets(2));
      // CU-35 soft-fail: la evidencia fuera de obra queda marcada.
      expect(find.text(ClosenessValidator.mismatchLabel), findsOneWidget);
      expect(find.text('Ver galería y mapa'), findsOneWidget);
    });

    testWidgets('sin evidencias muestra el mensaje exacto del Alt. 2.1/2.2',
        (tester) async {
      await _pumpDetail(tester, dao: _FakeEvidenceDao());

      expect(
        find.text(MilestoneDetailScreen.emptyEvidenceMessage),
        findsOneWidget,
      );
      expect(
        find.text('Sin evidencia registrada para esta etapa'),
        findsOneWidget,
      );
      expect(find.text('GALERÍA DE EVIDENCIAS (0)'), findsNothing);
      // La metadata del hito sigue visible aunque no haya evidencia.
      expect(find.text('Cimientos'), findsOneWidget);
    });
  });
}
