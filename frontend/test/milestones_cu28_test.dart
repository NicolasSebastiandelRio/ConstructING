import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/features/milestones/domain/entities/milestone.dart';
import 'package:constructing_mobile/features/milestones/domain/validation/progression_guard.dart';

Milestone _hito(String id, String nombre, MilestoneStatus estado) => Milestone(
      id: id,
      obraId: 'w1',
      nombre: nombre,
      duracionDias: 3,
      estado: estado,
    );

void main() {
  group('ProgressionGuard - CU-28 (Validar Progresión de Estado)', () {
    test('autoriza si el hito no tiene predecesores', () {
      final check = ProgressionGuard.canAdvance(
        hitoId: 'a',
        byId: {'a': _hito('a', 'A', MilestoneStatus.pendiente)},
        edges: const {},
      );

      expect(check.allowed, isTrue);
      expect(check.blocking, isEmpty);
    });

    test('autoriza si todos los predecesores están Certificados (paso 4)', () {
      final check = ProgressionGuard.canAdvance(
        hitoId: 'c',
        byId: {
          'a': _hito('a', 'Cimientos', MilestoneStatus.certificado),
          'b': _hito('b', 'Muros', MilestoneStatus.certificado),
          'c': _hito('c', 'Techo', MilestoneStatus.pendiente),
        },
        edges: {
          'c': {'a', 'b'},
        },
      );

      expect(check.allowed, isTrue);
    });

    test('deniega si un predecesor está Pendiente (Alt. 2.1/2.2)', () {
      final check = ProgressionGuard.canAdvance(
        hitoId: 'b',
        byId: {
          'a': _hito('a', 'Cimientos', MilestoneStatus.pendiente),
          'b': _hito('b', 'Muros', MilestoneStatus.pendiente),
        },
        edges: {
          'b': {'a'},
        },
      );

      expect(check.allowed, isFalse);
      expect(check.blocking, ['Cimientos']);
      expect(
        ProgressionGuard.denialMessage(check),
        'El hito está bloqueado hasta que se certifiquen: Cimientos.',
      );
    });

    test('deniega si un predecesor está En Ejecución y lista todos', () {
      final check = ProgressionGuard.canAdvance(
        hitoId: 'd',
        byId: {
          'a': _hito('a', 'Cimientos', MilestoneStatus.certificado),
          'b': _hito('b', 'Muros', MilestoneStatus.enEjecucion),
          'c': _hito('c', 'Techo', MilestoneStatus.pendiente),
          'd': _hito('d', 'Pintura', MilestoneStatus.pendiente),
        },
        edges: {
          'd': {'a', 'b', 'c'},
        },
      );

      expect(check.allowed, isFalse);
      expect(check.blocking, containsAll(['Muros', 'Techo']));
      expect(check.blocking, isNot(contains('Cimientos')));
    });

    test('falla cerrado ante arista corrupta (predecesor inexistente)', () {
      final check = ProgressionGuard.canAdvance(
        hitoId: 'a',
        byId: {'a': _hito('a', 'A', MilestoneStatus.pendiente)},
        edges: {
          'a': {'fantasma'},
        },
      );

      expect(check.allowed, isFalse);
      expect(check.blocking, ['fantasma']);
    });

    test('ignora las aristas de otros hitos', () {
      final check = ProgressionGuard.canAdvance(
        hitoId: 'a',
        byId: {
          'a': _hito('a', 'A', MilestoneStatus.pendiente),
          'b': _hito('b', 'B', MilestoneStatus.pendiente),
        },
        edges: {
          'b': {'a'},
        },
      );

      expect(check.allowed, isTrue);
    });
  });
}
