/// Estrategia de producto de ConstructING (decisión documentada en código).
///
/// - **Desarrollo mobile-first**: la UI se diseña y se prueba con mentalidad
///   móvil primero (layouts compactos, táctil, pantallas angostas). Todo el
///   código de `lib/` sigue esta orientación.
/// - **Entrega como URL web**: el producto final NO es una app descargable
///   (sin APK/AAB ni App Store). El artefacto distribuible se genera con
///   `flutter build web` y se sirve desde hosting estático como una URL.
///   La configuración web vive en `web/` (`index.html`, `manifest.json`).
/// - Esta clase existe para que la decisión sea explícita, centralizada y
///   verificable por tests (`test/deployment_test.dart`).
class DeploymentConfig {
  DeploymentConfig._();

  /// La UI se desarrolla con orientación mobile-first.
  static const bool mobileFirstDevelopment = true;

  /// El producto final se entrega como URL web, no como app instalable.
  static const bool deployAsWebUrl = true;

  /// Las tiendas de apps (Play Store / App Store) NO son canal de entrega.
  static const bool skipAppStores = true;
}
