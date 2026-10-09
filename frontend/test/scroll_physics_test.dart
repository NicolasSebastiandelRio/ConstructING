import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/theme/app_scroll_behavior.dart';

/// Scroll físico (transversal a todas las vistas): el contenido NO se estira
/// ni rebota al llegar a un tope. El gesto de más se descarta y la vista "cae"
/// como contenido normal.
void main() {
  /// Cadena de física efectiva (`AlwaysScrollableScrollPhysics -> ...`).
  String cadenaDe(ScrollPhysics? physics) {
    final nombres = <String>[];
    var actual = physics;
    while (actual != null) {
      nombres.add(actual.runtimeType.toString());
      actual = actual.parent;
    }
    return nombres.join(' -> ');
  }

  Widget lista({ScrollBehavior? behavior}) => MaterialApp(
        scrollBehavior: behavior,
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 60; i++)
                SizedBox(height: 40, child: Text('item $i')),
            ],
          ),
        ),
      );

  group('AppScrollBehavior - CU transversal (scroll sin estiramiento)', () {
    testWidgets(
        'en iOS también clampa: anula el rebote elástico del motor (donde '
        'Material devolvería BouncingScrollPhysics)', (tester) async {
      // El binding verifica las variables de depuración al cerrar el cuerpo:
      // el override se restaura dentro del propio test.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        late BuildContext ctx;
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
            ctx = context;
            return const SizedBox();
          }),
        ));

        // Control: el behavior de Material en iOS SÍ rebota.
        expect(const MaterialScrollBehavior().getScrollPhysics(ctx),
            isA<BouncingScrollPhysics>());
        // El behavior de la app no.
        const app = AppScrollBehavior();
        expect(app.getScrollPhysics(ctx), isA<ClampingScrollPhysics>());
        expect(app.getScrollPhysics(ctx), isNot(isA<BouncingScrollPhysics>()));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
        'registrado en MaterialApp: el motor efectivo termina en Clamping y '
        'desaparece el indicador de estiramiento (Android 12+)', (tester) async {
      await tester.pumpWidget(lista(behavior: const AppScrollBehavior()));
      await tester.pumpAndSettle();

      expect(find.byType(StretchingOverscrollIndicator), findsNothing);

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final cadena = cadenaDe(position.physics);
      expect(cadena, contains('ClampingScrollPhysics'));
      expect(cadena, isNot(contains('BouncingScrollPhysics')));
    });

    testWidgets(
        'deslizar más allá del tope superior NO deforma el contenido: el '
        'offset se queda en 0 durante el gesto', (tester) async {
      await tester.pumpWidget(lista(behavior: const AppScrollBehavior()));
      await tester.pumpAndSettle();

      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.pixels, 0.0);

      // Arrastre hacia abajo (over-scroll por el tope superior).
      final gesture =
          await tester.startGesture(tester.getCenter(find.byType(ListView)));
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      // Sin elasticidad: el contenido no se mueve ni se estira.
      expect(position.pixels, 0.0);

      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      expect(position.pixels, 0.0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(position.pixels, 0.0);
    });

    testWidgets('control: sin el behavior, Android sí estira el contenido',
        (tester) async {
      await tester.pumpWidget(lista());
      await tester.pumpAndSettle();

      // El indicador de estiramiento de Android 12+ está presente por
      // defecto: es el que "deforma" la vista en el over-scroll.
      expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
    });
  });
}
