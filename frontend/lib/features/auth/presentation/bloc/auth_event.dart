import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object> get props => [];
}

class LoginButtonPressed extends AuthEvent {
  final String email;
  final String password;
  final String role;

  const LoginButtonPressed({
    required this.email,
    required this.password,
    required this.role,
  });

  @override
  List<Object> get props => [email, password, role];
}

class LogoutRequested extends AuthEvent {}