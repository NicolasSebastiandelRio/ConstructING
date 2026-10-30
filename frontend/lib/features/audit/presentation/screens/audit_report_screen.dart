import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/storage/local_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/audit_log_local_data_source.dart';
import '../../data/datasources/audit_log_remote_data_source.dart';
import '../bloc/audit_report_bloc.dart';
import '../bloc/audit_report_state.dart';

/// CU-63 (RF_08, RNF_U_03): Reporte de Auditoría de la obra.
///
/// Paso 2: consulta todos los registros inmutables del `audit_log` de la obra
/// ordenados cronológicamente. Paso 4: renderiza la tabla con **quién** hizo
/// la acción, el **instante de tiempo exacto** y desde **qué ubicación**.
///
/// Poscondición: el usuario visualiza la hoja de ruta forense del proyecto.
class AuditReportScreen extends StatefulWidget {
  final String obraId;
  final String obraNombre;

  /// DAO inyectables (tests); en producción sobre la BD local real.
  final AuditLogLocalDataSource? auditLogDao;
  final AuditLogRemoteDataSource? remote;

  /// CU-63 "quién": resolutor opcional del nombre del actor.
  final Future<String?> Function(String usuarioId)? usuarioNombre;

  /// CU-63: `true` cuando la pantalla se embebe como pestaña "Auditoría"
  /// dentro del panel de la obra (sin `AppBar` propia, la provee el detalle).
  final bool embedded;

  const AuditReportScreen({
    super.key,
    required this.obraId,
    required this.obraNombre,
    this.auditLogDao,
    this.remote,
    this.usuarioNombre,
    this.embedded = false,
  });

  /// Estado vacío de la hoja forense.
  static const String emptyStateMessage =
      'Sin registros de auditoría para esta obra';

  @override
  State<AuditReportScreen> createState() => _AuditReportScreenState();
}

class _AuditReportScreenState extends State<AuditReportScreen> {
  late final AuditReportBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = AuditReportBloc(
      local: widget.auditLogDao ??
          AuditLogLocalDataSource(localDatabase: LocalDatabase()),
      remote: widget.remote,
      usuarioNombre: widget.usuarioNombre,
    )..add(LoadAuditReport(obraId: widget.obraId));
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuditReportBloc>.value(
      value: _bloc,
      child: Scaffold(
        backgroundColor: AppTheme.darkSurface,
        appBar: widget.embedded
            ? null
            : AppBar(
                backgroundColor: Colors.transparent,
                title: const Text(
                  'REPORTE DE AUDITORÍA',
                  style: TextStyle(
                      fontFamily: 'Cinzel',
                      color: AppTheme.accentGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
                iconTheme: const IconThemeData(color: AppTheme.accentGold),
              ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Hoja de ruta forense de "${widget.obraNombre}"',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12),
              ),
            ),
            Expanded(
              child: BlocBuilder<AuditReportBloc, AuditReportState>(
                builder: (context, state) {
                  if (state is AuditReportLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.accentGold),
                    );
                  }
                  if (state is AuditReportError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(state.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppTheme.primaryRed)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => context
                                .read<AuditReportBloc>()
                                .add(LoadAuditReport(obraId: widget.obraId)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentGold,
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (state is AuditReportLoaded) {
                    if (state.registros.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            AuditReportScreen.emptyStateMessage,
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      // Scroll físico: sin estiramiento en los topes.
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: state.registros.length + 1,
                      itemBuilder: (context, index) {
                        // Encabezado de la tabla (CU-63 paso 4).
                        if (index == 0) return const _ReportHeader();
                        final registro = state.registros[index - 1];
                        return _AuditRow(
                          posicion: index,
                          actor: state.actorDe(registro),
                          instante: _instante(registro.createdAt),
                          ubicacion: _ubicacion(registro.coordenadas),
                          accion: accionLegible(registro.accion),
                          detalle: registro.detalle,
                        );
                      },
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// CU-63 paso 4: instante de tiempo exacto (DD/MM/AAAA HH:MM:SS).
  static String _instante(DateTime fecha) {
    final f = fecha.toLocal();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${dos(f.day)}/${dos(f.month)}/${f.year} '
        '${dos(f.hour)}:${dos(f.minute)}:${dos(f.second)}';
  }

  /// CU-63 paso 4: desde qué ubicación se ejecutó la acción.
  static String _ubicacion(String? coordenadas) {
    final raw = coordenadas?.trim();
    if (raw == null || raw.isEmpty) return 'Sin ubicación registrada';
    return raw;
  }
}

/// Encabezado de la tabla forense.
class _ReportHeader extends StatelessWidget {
  const _ReportHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.history_edu,
              color: AppTheme.accentGold, size: 16),
          const SizedBox(width: 6),
          Text(
            'TRAZABILIDAD INMUTABLE (RNF_S_03)',
            style: TextStyle(
              fontFamily: 'Cinzel',
              color: AppTheme.accentGold.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// CU-63/RNF_U_03: nombre legible de cada acción auditada (CU-60).
///
/// Los códigos internos (`hito_creado`, `acta_sellada`, …) no le dicen nada
/// al usuario; el reporte muestra la acción en lenguaje natural y, si
/// aparece un código nuevo sin traducir, lo humaniza en vez de ocultarlo.
String accionLegible(String accion) {
  switch (accion) {
    case 'hito_creado':
      return 'Hito creado';
    case 'hito_modificado':
      return 'Hito modificado';
    case 'hito_iniciado':
      return 'Hito iniciado';
    case 'hito_certificado':
      return 'Hito certificado';
    case 'hito_eliminado':
      return 'Hito eliminado';
    case 'dependencias_actualizadas':
      return 'Dependencias actualizadas';
    case 'certificacion_solicitada':
      return 'Certificación solicitada';
    case 'conformidad_firmada':
      return 'Firma registrada';
    case 'acta_sellada':
      return 'Acta firmada y sellada';
    case 'evidencia_cargada':
      return 'Evidencia cargada';
    case 'obra_creada':
      return 'Obra creada';
    case 'obra_modificada':
      return 'Obra modificada';
    case 'obra_estado_actualizado':
      return 'Estado de la obra actualizado';
    case 'obra_archivada':
      return 'Obra archivada';
    default:
      // Código desconocido: se humaniza (guion bajo -> espacio, inicial
      // mayúscula) en lugar de esconder la traza.
      final texto = accion.replaceAll('_', ' ').trim();
      if (texto.isEmpty) return 'Acción registrada';
      return texto[0].toUpperCase() + texto.substring(1);
  }
}

/// Fila del reporte: quién · cuándo · dónde · qué (CU-63 paso 4).
class _AuditRow extends StatelessWidget {
  final int posicion;
  final String actor;
  final String instante;
  final String ubicacion;
  final String accion;
  final String? detalle;

  const _AuditRow({
    required this.posicion,
    required this.actor,
    required this.instante,
    required this.ubicacion,
    required this.accion,
    this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentGold.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.accentGold.withValues(alpha: 0.8)),
                ),
                child: Text('$posicion',
                    style: const TextStyle(
                        color: AppTheme.accentGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  accion,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Campo(
            icono: Icons.person_outline,
            etiqueta: 'Quién',
            valor: actor,
            color: AppTheme.lightBlue,
          ),
          _Campo(
            icono: Icons.schedule,
            etiqueta: 'Instante',
            valor: instante,
            color: AppTheme.accentGold,
          ),
          _Campo(
            icono: Icons.location_on_outlined,
            etiqueta: 'Ubicación',
            valor: ubicacion,
            color: Colors.white70,
          ),
          if (detalle != null && detalle!.trim().isNotEmpty)
            _Campo(
              icono: Icons.notes,
              etiqueta: 'Detalle',
              valor: detalle!,
              color: Colors.white60,
            ),
        ],
      ),
    );
  }
}

class _Campo extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color color;

  const _Campo({
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 13, color: color),
          const SizedBox(width: 6),
          SizedBox(
            width: 62,
            child: Text('$etiqueta:',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          Expanded(
            child: Text(valor,
                style: TextStyle(color: color, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
