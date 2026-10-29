/// Roles de la conformidad colegiada del acta (CU-57, RF_05/RNF_C_05).
///
/// Norma del flujo de certificación del Sprint 5:
/// 1. El **profesional responsable** certifica técnicamente el hito: su
///    firma ABRE la conformidad colegiada y queda persistida como borrador
///    (`conformidades_pendientes`), pendiente de la segunda firma.
/// 2. El **propietario** solo puede firmar LUEGO y SOLO SI ese borrador
///    existe (su Hoja de Ruta lo muestra "esperando su firma"). Sin la
///    conformidad técnica previa no puede forzar la certificación.
/// 3. El acta se compila, se sella (CU-59) y el hito se congela (CU-57)
///    únicamente cuando aparecen AMBAS firmas, de dos actores distintos.
///
/// El mismo rol NUNCA firma dos veces: un acta con doble firma exige dos
/// actores reales.
abstract final class ConformidadRoles {
  static const String profesional = 'Profesional';
  static const String propietario = 'Propietario';

  /// Rol que abre siempre la conformidad colegiada (primera firma).
  static const String primerFirmante = profesional;

  /// La contraparte de [rol] en la conformidad colegiada.
  static String otraParte(String rol) =>
      rol == profesional ? propietario : profesional;

  /// ¿El borrador nació de la conformidad técnica del profesional
  /// responsable? Un borrador que no cumple esta precondición no puede
  /// cerrarse: sería un sello con una firma fabricada.
  static bool esPrimerFirmanteValido(String rol) => rol == primerFirmante;
}
