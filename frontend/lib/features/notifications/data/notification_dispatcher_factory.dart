import '../../../core/storage/local_database.dart';
import 'datasources/notification_local_data_source.dart';
import 'notification_dispatcher.dart';

/// CU-67/CU-68: construye el despachador de alertas sobre la BD local real.
///
/// Punto ÚNICO que usan las pantallas de captura y de certificación. Antes
/// esos BLoC recibían `notificationDispatcher: null` —el parámetro existía
/// pero ninguna pantalla lo pasaba— así que el motor de alertas nunca se
/// disparaba y la campana quedaba siempre vacía para ambos roles.
NotificationDispatcher buildNotificationDispatcher({LocalDatabase? database}) {
  final db = database ?? LocalDatabase();
  return NotificationDispatcher(
    local: NotificationLocalDataSource(localDatabase: db),
  );
}
