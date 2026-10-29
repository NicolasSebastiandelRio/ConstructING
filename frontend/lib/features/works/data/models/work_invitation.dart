/// Invitación de obra (CU-22): código único temporal asociado a una obra para
/// que un propietario no registrado se una al registrarse.
class WorkInvitation {
  final String id;
  final String code;
  final String workId;
  final String email;
  final DateTime? expiresAt;
  final DateTime? usedAt;

  const WorkInvitation({
    required this.id,
    required this.code,
    required this.workId,
    required this.email,
    this.expiresAt,
    this.usedAt,
  });

  factory WorkInvitation.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    return WorkInvitation(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      workId: json['workId'] ?? json['work_id'] ?? '',
      email: json['email'] ?? '',
      expiresAt: parseDate(json['expiresAt']),
      usedAt: parseDate(json['usedAt']),
    );
  }
}