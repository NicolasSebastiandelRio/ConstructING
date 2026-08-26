import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/work_entity.dart';

class WorkDetailScreen extends StatelessWidget {
  final WorkEntity work;
  final String userRole; // <-- Agregado para Control de Acceso (RBAC)

  const WorkDetailScreen({super.key, required this.work, required this.userRole});

  bool get _isProfesional => userRole.toLowerCase().contains('profesional');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          work.nombre,
          style: const TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.accentGold),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Renderizado condicional: Solo el Profesional ve las opciones operativas (CU-17, CU-20, CU-21)
          if (_isProfesional)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppTheme.accentGold),
              color: AppTheme.darkSurface,
              onSelected: (value) {
                if (value == 'edit') {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edición en construcción (CU-17)')));
                } else if (value == 'status') {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Actualización de Estado en construcción (CU-20)')));
                } else if (value == 'archive') {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Borrado Lógico en construcción (CU-21)')));
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined, color: AppTheme.accentGold),
                    title: Text('Editar Obra', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'status',
                  child: ListTile(
                    leading: Icon(Icons.update, color: AppTheme.lightBlue),
                    title: Text('Actualizar Estado', style: TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ),
                const PopupMenuDivider(height: 1),
                const PopupMenuItem<String>(
                  value: 'archive',
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined, color: AppTheme.primaryRed),
                    title: Text('Archivar Proyecto', style: TextStyle(color: AppTheme.primaryRed, fontSize: 14)),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabecera con Ubicación y Estado
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentGold.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Estado Actual', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: work.estado == 'Finalizado' ? Colors.green.shade800 : AppTheme.lightBlue.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(work.estado, style: const TextStyle(color: AppTheme.lightBlue, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Ubicación', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: AppTheme.accentGold, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(work.direccion, style: const TextStyle(color: Colors.white, fontSize: 14))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Fecha de Inicio', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(work.fechaInicio, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Sección de Línea de Tiempo / Hitos (Mockup 7)
              const Text(
                'LÍNEA DE TIEMPO DEL PROYECTO',
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  color: AppTheme.accentGold,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'No hay hitos registrados en este proyecto todavía.\n(Módulo de Hitos - Sprint 3)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}