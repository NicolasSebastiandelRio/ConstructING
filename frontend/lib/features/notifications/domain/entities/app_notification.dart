import 'package:equatable/equatable.dart';

/// CU-67/CU-68/CU-69 (RF_10): tipos de alerta del motor de notificaciones.
enum NotificationTipo {
  /// CU-67: actualización de obra (cierre de hito / subida de evidencia).
  avance('avance', 'Avance de obra'),

  /// CU-68: acta lista para firmar (alta prioridad).
  firma('firma', 'Solicitud de firma'),

  /// CU-69: desvío temporal de un hito de ruta crítica.
  retraso('retraso', 'Alerta de retraso');

  const NotificationTipo(this.code, this.label);

  final String code;
  final String label;

  static NotificationTipo fromCode(String code) {
    for (final tipo in NotificationTipo.values) {
      if (tipo.code == code) return tipo;
    }
    return NotificationTipo.avance;
  }
}

/// Prioridad del despacho: CU-68 exige alta prioridad explícita.
enum NotificationPrioridad {
  alta('alta'),
  normal('normal');

  const NotificationPrioridad(this.code);

  final String code;

  static NotificationPrioridad fromCode(String code) =>
      code == 'alta' ? NotificationPrioridad.alta : NotificationPrioridad.normal;
}

/// CU-70/CU-72 (RF_10): alerta de la bandeja de entrada de un usuario.
///
/// Vive en la BD local (offline-first) con su estado de lectura: el badge de
/// la campana se calcula sobre `leida == false` (CU-72).
class AppNotification extends Equatable {
  final String id;

  /// Destinatario de la alerta (`ID de usuario`, CU-67 paso 1).
  final String usuarioId;

  final NotificationTipo tipo;
  final String titulo;
  final String mensaje;

  /// Enlace directo a la obra (CU-67 paso 4) y al hito cuando aplica.
  final String? obraId;
  final String? hitoId;

  final NotificationPrioridad prioridad;
  final bool leida;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.usuarioId,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.obraId,
    this.hitoId,
    this.prioridad = NotificationPrioridad.normal,
    this.leida = false,
    required this.createdAt,
  });

  AppNotification copyWith({bool? leida}) => AppNotification(
        id: id,
        usuarioId: usuarioId,
        tipo: tipo,
        titulo: titulo,
        mensaje: mensaje,
        obraId: obraId,
        hitoId: hitoId,
        prioridad: prioridad,
        leida: leida ?? this.leida,
        createdAt: createdAt,
      );

  Map<String, dynamic> toLocalDb() => {
        'id': id,
        'usuario_id': usuarioId,
        'tipo': tipo.code,
        'titulo': titulo,
        'mensaje': mensaje,
        'obra_id': obraId,
        'hito_id': hitoId,
        'prioridad': prioridad.code,
        'leida': leida ? 1 : 0,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory AppNotification.fromLocalDb(Map<String, dynamic> row) =>
      AppNotification(
        id: row['id'] as String,
        usuarioId: row['usuario_id'] as String,
        tipo: NotificationTipo.fromCode(row['tipo'] as String? ?? ''),
        titulo: row['titulo'] as String? ?? '',
        mensaje: row['mensaje'] as String? ?? '',
        obraId: row['obra_id'] as String?,
        hitoId: row['hito_id'] as String?,
        prioridad:
            NotificationPrioridad.fromCode(row['prioridad'] as String? ?? ''),
        leida: (row['leida'] as int? ?? 0) == 1,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
            DateTime.now(),
      );

  /// Payload del endpoint `POST /notifications` (mismo contrato que el
  /// snapshot en la base maestra).
  Map<String, dynamic> toRemoteJson() => {
        'id': id,
        'usuarioId': usuarioId,
        'tipo': tipo.code,
        'titulo': titulo,
        'mensaje': mensaje,
        'obraId': obraId,
        'hitoId': hitoId,
        'prioridad': prioridad.code,
        'leida': leida,
      };

  factory AppNotification.fromRemoteJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        usuarioId: json['usuarioId'] as String,
        tipo: NotificationTipo.fromCode(json['tipo'] as String? ?? ''),
        titulo: json['titulo'] as String? ?? '',
        mensaje: json['mensaje'] as String? ?? '',
        obraId: json['obraId'] as String?,
        hitoId: json['hitoId'] as String?,
        prioridad:
            NotificationPrioridad.fromCode(json['prioridad'] as String? ?? ''),
        leida: json['leida'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  @override
  List<Object?> get props => [
        id,
        usuarioId,
        tipo,
        titulo,
        mensaje,
        obraId,
        hitoId,
        prioridad,
        leida,
        createdAt,
      ];
}

/// CU-71 (RF_10): preferencias de canal de alerta del usuario.
class NotificationPreferences extends Equatable {
  final String usuarioId;

  /// "Recibir por correo": si está activo el despacho usa correo (además de
  /// la bandeja in-app); si no, solo la alerta in-app/push.
  final bool recibirPorCorreo;

  const NotificationPreferences({
    required this.usuarioId,
    this.recibirPorCorreo = true,
  });

  NotificationPreferences copyWith({bool? recibirPorCorreo}) =>
      NotificationPreferences(
        usuarioId: usuarioId,
        recibirPorCorreo: recibirPorCorreo ?? this.recibirPorCorreo,
      );

  Map<String, dynamic> toLocalDb() => {
        'usuario_id': usuarioId,
        'recibir_por_correo': recibirPorCorreo ? 1 : 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory NotificationPreferences.fromLocalDb(Map<String, dynamic> row) =>
      NotificationPreferences(
        usuarioId: row['usuario_id'] as String,
        recibirPorCorreo: (row['recibir_por_correo'] as int? ?? 1) == 1,
      );

  factory NotificationPreferences.fromRemoteJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        usuarioId: json['usuarioId'] as String,
        recibirPorCorreo: json['recibirPorCorreo'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [usuarioId, recibirPorCorreo];
}
