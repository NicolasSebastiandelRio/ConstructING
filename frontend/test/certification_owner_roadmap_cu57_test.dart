import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/storage/local_database.dart';
import 'package:constructing_mobile/features/certification/data/datasources/certification_local_data_source.dart';
import 'package:constructing_mobile/features/certification/domain/conformidad_roles.dart';
import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/presentation/widgets/milestones_section.dart';

import 'milestones_test_helpers.dart';

/// DAO de conformidades pendientes en memoria (los widget tests no abren BD
/// real: el FFI cuelga la finalización del test). Extiende el DAO real para
/// heredar la firma y anular solo el acceso a datos.
class _FakePendingConformidadDao extends PendingConformidadDataSource {
  _FakePendingConformidadDao() : super(localDatabase: LocalDatabase());

  final Map<String, PendingConformidad> _store = {};

  void seed(PendingConformidad conformidad) {
    _store[conformidad.hitoId] = conformidad;
  }

  @override
  Future<PendingConformidad> save(PendingConformidad conformidad) async {
    _store[conformidad.hitoId] = conformidad;
    return conformidad;
  }

  @override
  Future<PendingConformidad?> findPending(String hitoId) async =>
      _store[hitoId];

  @override
  Future<List<PendingConformidad>> listByObra(String obraId) async =>
      _store.values.where((c) => c.obraId == obraId).toList();

  @override
  Future<void> delete(String hitoId) async {
    _store.remove(hitoId);
  }
}

PendingConformidad _borrador({required String hitoId, required String rol}) =>
    PendingConformidad(
      hitoId: hitoId,
      obraId: 'w1',
      primerFirmante: rol,
      primerTrazos: const [],
      primerMetadatos: const {},
      primerFecha: DateTime(2026, 9, 1, 10),
      createdAt: DateTime(2026, 9, 1, 10),
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool isProfesional,
  required _FakePendingConformidadDao pendientes,
}) async {
  final dao = FakeMilestoneDao();
  dao.seed([
    const Milestone(
      id: 'h1',
      obraId: 'w1',
      nombre: 'Cimientos',
      duracionDias: 5,
      estado: MilestoneStatus.enEjecucion,
    ),
  ]);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MilestonesSection(
          obraId: 'w1',
          isProfesional: isProfesional,
          dataSource: dao,
          pendingConformidadDao: pendientes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Hoja de Ruta del Propietario - CU-57 (esperando su firma)', () {
    testWidgets(
        'con la conformidad del profesional pendiente el hito queda '
        '"ESPERANDO SU FIRMA" y el Propietario recibe la acción de firmar',
        (tester) async {
      final pendientes = _FakePendingConformidadDao()
        ..seed(_borrador(hitoId: 'h1', rol: ConformidadRoles.profesional));

      await _pump(tester, isProfesional: false, pendientes: pendientes);

      expect(find.text('ESPERANDO SU FIRMA (CU-57)'), findsOneWidget);
      expect(find.byTooltip('Firmar conformidad (Propietario)'), findsOneWidget);
      // El Propietario nunca "certifica la etapa": eso es del profesional.
      expect(find.byTooltip('Certificar etapa'), findsNothing);
    });

    testWidgets(
        'SIN la primera firma del profesional, el Propietario no recibe '
        'ninguna acción de certificación: no puede forzar el cierre',
        (tester) async {
      await _pump(
        tester,
        isProfesional: false,
        pendientes: _FakePendingConformidadDao(),
      );

      expect(find.textContaining('ESPERANDO SU FIRMA'), findsNothing);
      expect(find.byTooltip('Firmar conformidad (Propietario)'), findsNothing);
      expect(find.byTooltip('Certificar etapa'), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);
      expect(find.byIcon(Icons.draw_outlined), findsNothing);
    });

    testWidgets(
        'el profesional ve la conformidad registrada esperando al Propietario '
        'y conserva su acción de cierre',
        (tester) async {
      final pendientes = _FakePendingConformidadDao()
        ..seed(_borrador(hitoId: 'h1', rol: ConformidadRoles.profesional));

      await _pump(tester, isProfesional: true, pendientes: pendientes);

      expect(
        find.text('CONFORMIDAD REGISTRADA · ESPERANDO FIRMA DEL PROPIETARIO'),
        findsOneWidget,
      );
      expect(find.byTooltip('Certificar etapa'), findsOneWidget);
      expect(find.byTooltip('Firmar conformidad (Propietario)'), findsNothing);
    });
  });
}
