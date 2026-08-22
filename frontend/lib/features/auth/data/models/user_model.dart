import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required String id,
    required String nombre,
    required String email,
    required String rol,
    String? matricula,
  }) : super(
          id: id,
          nombre: nombre,
          email: email,
          rol: rol,
          matricula: matricula,
        );

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? '',
      email: json['email'] ?? '',
      rol: json['rol'] ?? 'Propietario',
      matricula: json['matricula'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'email': email,
      'rol': rol,
      'matricula': matricula,
    };
  }
}