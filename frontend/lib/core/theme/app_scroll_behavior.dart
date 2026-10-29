import 'package:flutter/material.dart';

/// Comportamiento de scroll físico de ConstructING.
///
/// Objetivo transversal a TODAS las vistas (dashboard de obras, Hoja de Ruta,
/// detalle de hito, resumen de certificación, capture flow, visor de
/// evidencias, formularios y modales): al llegar a un tope, el contenido NO
/// se estira ni rebota. El gesto de más se descarta y la vista "cae" como
/// contenido normal.
///
/// - [getScrollPhysics]: `ClampingScrollPhysics` en TODOS los motores
///   (Android, iOS, web, escritorio). Anula el rebote elástico de
///   `BouncingScrollPhysics` (iOS/web) y el estiramiento de Android 12+.
/// - [buildOverscrollIndicator]: devuelve el hijo sin indicador. El
///   `StretchingOverscrollIndicator` (Android 12+) deforma el contenido en el
///   over-scroll; el `GlowingOverscrollIndicator` clásico pinta un halo sobre
///   el borde. Ninguno de los dos aplica aquí.
///
/// Se registra una sola vez en `MaterialApp.scrollBehavior` (main.dart), de
/// modo que cubre vistas, diálogos, bottom sheets y listas anidadas sin
/// repetir `physics:` en cada scrollable. Aun así los scrollables principales
/// declaran `physics: const ClampingScrollPhysics()` de forma explícita, para
/// que el tope sea duro aunque el widget se monte fuera del `MaterialApp`.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
