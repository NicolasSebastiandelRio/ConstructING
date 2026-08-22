import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'core/network/dio_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/datasources/auth_remote_data_source.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/screens/welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Instanciación de dependencias core
  const secureStorage = FlutterSecureStorage();
  final dioClient = DioClient();
  final authRemoteDataSource = AuthRemoteDataSourceImpl(dioClient: dioClient);

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc(
            authRemoteDataSource: authRemoteDataSource,
            secureStorage: secureStorage,
          ),
        ),
      ],
      child: const ConstructINGApp(),
    ),
  );
}

class ConstructINGApp extends StatelessWidget {
  const ConstructINGApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConstructING',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const WelcomeScreen(),
    );
  }
}