import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/users_remote_data_source.dart';
import '../../data/models/user_model.dart';
import '../../../../core/network/dio_client.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late final UsersRemoteDataSource _dataSource;
  List<UserModel> _usuarios = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _dataSource = UsersRemoteDataSourceImpl(dioClient: DioClient());
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final users = await _dataSource.getUsers();
      setState(() {
        _usuarios = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GESTIÓN DE USUARIOS',
          style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.accentGold),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o email...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.accentGold),
                  filled: true,
                  fillColor: AppTheme.darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.accentGold))
                    : _errorMessage.isNotEmpty
                        // CU-09 Flujo Alt. 2.2: ante un error de conexión se
                        // informa el problema y se sugiere recargar la página.
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_errorMessage, style: const TextStyle(color: AppTheme.primaryRed), textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _loadUsers,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reintentar'),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGold, foregroundColor: Colors.black),
                                ),
                              ],
                            ),
                          )
                        : _usuarios.isEmpty
                            ? const Center(child: Text('No hay usuarios registrados.', style: TextStyle(color: Colors.white54)))
                            : ListView.builder(
                                itemCount: _usuarios.length,
                                itemBuilder: (context, index) {
                                  final user = _usuarios[index];
                                  final isActive = user.deletedAt == null;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.darkSurface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppTheme.accentGold.withOpacity(0.3)),
                                    ),
                                    child: ListTile(
                                      title: Text(
                                        user.nombre,
                                        style: const TextStyle(color: AppTheme.accentGold, fontWeight: FontWeight.bold, fontFamily: 'Cinzel'),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(user.email, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          const SizedBox(height: 4),
                                          Text('Rol: ${user.rol} | Estado: ${isActive ? 'Activo' : 'Inhabilitado'}',
                                            style: TextStyle(color: isActive ? Colors.greenAccent : AppTheme.primaryRed, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert, color: AppTheme.accentGold),
                                        color: AppTheme.darkSurface,
                                        onSelected: (val) async {
                                          if (val == 'edit') {
                                            await _openEditDialog(user);
                                          } else if (val == 'toggle') {
                                            if (isActive) {
                                              // CU-08 pasos 2-3: confirmación de seguridad en pantalla.
                                              await _confirmDisableDialog(user);
                                            } else {
                                              try {
                                                await _dataSource.restoreUser(user.id);
                                                await _loadUsers();
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Usuario habilitado exitosamente (CU-08).')),
                                                );
                                              } catch (e) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.primaryRed),
                                                );
                                              }
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: const Text('Editar Datos (CU-07)', style: TextStyle(color: AppTheme.accentGold)),
                                          ),
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Text(
                                              isActive ? 'Inhabilitar (Soft-Delete)' : 'Habilitar',
                                              style: TextStyle(color: isActive ? AppTheme.primaryRed : Colors.greenAccent),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// CU-08 pasos 2-3: solicita confirmación de seguridad antes de inhabilitar.
  /// Si el administrador cancela (Alt. 3.1), se cierra sin modificar la BD (3.2).
  Future<void> _confirmDisableDialog(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'CONFIRMAR INHABILITACIÓN',
          style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '¿Está seguro de inhabilitar a "${user.nombre}"?\n\nSu acceso quedará suspendido, pero sus obras y evidencias pasadas se conservarán.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryRed),
            child: const Text('Inhabilitar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return; // Alt. 3.1/3.2: cierra sin tocar la BD.

    try {
      await _dataSource.deleteUser(user.id);
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usuario inhabilitado exitosamente (CU-08).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.primaryRed),
      );
    }
  }

  /// CU-07: Abre el diálogo de edición con los datos actuales precargados,
  /// valida el formato ingresado y persiste en el backend.
  Future<void> _openEditDialog(UserModel user) async {
    final nombreController = TextEditingController(text: user.nombre);
    final emailController = TextEditingController(text: user.email);
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text(
          'EDITAR DATOS',
          style: TextStyle(fontFamily: 'Cinzel', color: AppTheme.accentGold, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nombreController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'Ej: Ana García',
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre no puede estar vacío.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'ejemplo@gmail.com',
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El correo no puede estar vacío.';
                    }
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Ingrese un correo electrónico válido.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña (opcional)',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintText: 'Mínimo 8 caracteres y un número',
                    hintStyle: TextStyle(color: Colors.white54),
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (value.length < 8 || !RegExp(r'\d').hasMatch(value)) {
                        return 'La contraseña debe tener al menos 8 caracteres y un número';
                      }
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await _dataSource.updateUser(
                  user.id,
                  nombre: nombreController.text.trim(),
                  email: emailController.text.trim(),
                  password: passwordController.text.isEmpty ? null : passwordController.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.primaryRed),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentGold),
            child: const Text('Guardar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (saved == true) {
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado exitosamente (CU-07).')),
      );
    }
  }
}