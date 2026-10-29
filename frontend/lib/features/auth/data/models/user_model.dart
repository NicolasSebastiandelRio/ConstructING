import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required String id,
    required String nombre,
    required String email,
    required String rol,
    String? matricula,
    DateTime? deletedAt,
  }) : super(
          id: id,
          nombre: nombre,
          email: email,
          rol: rol,
          matricula: matricula,
          deletedAt: deletedAt,
        );

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final rawDeletedAt = json['deletedAt'];
    return UserModel(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      email: json['email'] ?? '',
      rol: json['rol'] ?? 'Propietario',
      matricula: json['matricula'],
      deletedAt: rawDeletedAt != null ? DateTime.tryParse(rawDeletedAt as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'email': email,
      'rol': rol,
      'matricula': matricula,
      'deletedAt': deletedAt?.toIso8601String(),
    };
  }
}