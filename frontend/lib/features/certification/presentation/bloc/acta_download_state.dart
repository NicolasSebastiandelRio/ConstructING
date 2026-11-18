import 'package:equatable/equatable.dart';

abstract class ActaDownloadState extends Equatable {
  const ActaDownloadState();

  @override
  List<Object?> get props => [];
}

class ActaDownloadIdle extends ActaDownloadState {}

class ActaDownloading extends ActaDownloadState {}

/// CU-54 poscondición: el usuario posee una copia offline física de su
/// certificado técnico (paso 4).
class ActaDownloaded extends ActaDownloadState {
  final String fileName;
  final String ubicacion;

  /// Origen de los bytes: "caché local" o "servidor central" (paso 2).
  final String origen;

  const ActaDownloaded({
    required this.fileName,
    required this.ubicacion,
    required this.origen,
  });

  @override
  List<Object?> get props => [fileName, ubicacion, origen];
}

class ActaDownloadError extends ActaDownloadState {
  final String message;

  const ActaDownloadError({required this.message});

  @override
  List<Object?> get props => [message];
}
