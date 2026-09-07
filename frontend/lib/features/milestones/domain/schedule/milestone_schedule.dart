/// Vista de cronograma por hito para la Hoja de Ruta (roadmap).
///
/// Convierte el cómputo CPM (días relativos al inicio) en fechas concretas
/// ancladas a `obraStart`, más los días restantes que bajan con el paso del
/// tiempo. Todo puro y testeable; la UI solo formatea.
class MilestoneScheduleView {
  /// Inicio del hito (obraStart + earlyStart).
  final DateTime startDate;

  /// Fin estimado del hito (obraStart + earlyFinish), en formato fecha.
  final DateTime endDate;

  /// Días que faltan: duración menos los transcurridos desde el inicio
  /// (nunca negativo).
  final int remainingDays;

  final bool isCritical;

  const MilestoneScheduleView({
    required this.startDate,
    required this.endDate,
    required this.remainingDays,
    required this.isCritical,
  });

  /// Resuelve la vista de un hito. `now` es inyectable para tests.
  factory MilestoneScheduleView.resolve({
    required DateTime obraStart,
    required int earlyStart,
    required int earlyFinish,
    required int durationDays,
    required bool isCritical,
    DateTime? now,
  }) {
    final start = _addDays(obraStart, earlyStart);
    final end = _addDays(obraStart, earlyFinish);
    final today = _dayOf(now ?? DateTime.now());
    var elapsed = today.difference(_dayOf(start)).inDays;
    if (elapsed < 0) elapsed = 0;
    var remaining = durationDays - elapsed;
    if (remaining < 0) remaining = 0;
    return MilestoneScheduleView(
      startDate: start,
      endDate: end,
      remainingDays: remaining,
      isCritical: isCritical,
    );
  }

  /// Formato fecha argentino DD/MM/AAAA (convención de la app).
  static String format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  static DateTime _addDays(DateTime base, int days) =>
      _dayOf(base).add(Duration(days: days));

  static DateTime _dayOf(DateTime dateTime) =>
      DateTime(dateTime.year, dateTime.month, dateTime.day);
}
