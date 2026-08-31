import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/datasources/users_remote_data_source.dart';
import '../../data/models/user_model.dart';
import '../../../../core/network/dio_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
    _dataSource = UsersRemoteDataSourceImpl(
      dioClient: DioClient(),
      secureStorage: const FlutterSecureStorage(),
    );
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
                        ? Center(child: Text(_errorMessage, style: const TextStyle(color: AppTheme.primaryRed)))
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
                                          if (val == 'toggle') {
                                            try {
                                              await _dataSource.deleteUser(user.id);
                                              await _loadUsers();
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Estado de usuario modificado exitosamente (CU-08).')),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.primaryRed),
                                              );
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => [
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
}