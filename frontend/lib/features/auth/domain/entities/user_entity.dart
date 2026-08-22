class UserEntity {
  final String id;
  final String nombre;
  final String email;
  final String rol; // 'Profesional', 'Propietario', 'Administrador'
  final String? matricula;

  const UserEntity({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    this.matricula,
  });
}