import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../milestones/data/datasources/milestone_local_data_source.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../domain/certification_audit.dart';
import '../../gateway/acta_paths.dart';
import 'acta_download_state.dart';

/// Cubit de descarga del acta de conformidad (CU-54, RF_05).
///
/// Paso 2: localiza el PDF en el caché local o lo descarga desde el
/// servidor central. Paso 4: guarda la copia offline en el dispositivo y
/// notifica al usuario. Precondición: hito con estado "Certificado".
class ActaDownloadCubit extends Cubit<ActaDownloadState> {
  final MilestoneLocalDataSource milestoneDao;

  /// Lee el acta del caché local (null si no existe). Inyectable (tests).
  final Future<Uint8List?> Function(String hitoId) readCachedActa;

  /// Guarda el PDF y devuelve la ubicación resultante. Inyectable (tests).
  final Future<String> Function({
    required Uint8List bytes,
    required String fileName,
  }) saveActa;

  /// Fuente remota (servidor central); opcional hasta que el backend de
  /// certificaciones esté disponible. Inyectable como función (tests).
  final Future<Uint8List?> Function({required String hitoId})? remoteActa;

  ActaDownloadCubit({
    required this.milestoneDao,
    required this.readCachedActa,
    required this.saveActa,
    this.remoteActa,
  }) : super(ActaDownloadIdle());

  Future<void> download({required String hitoId}) async {
    emit(ActaDownloading());
    try {
      final hito = await milestoneDao.getById(hitoId);
      if (hito == null) {
        throw Exception('El hito ya no existe en la Hoja de Ruta.');
      }
      // Precondición: el acta se descarga desde un hito finalizado.
      if (hito.estado != MilestoneStatus.certificado) {
        throw Exception(
            'El acta se descarga desde un hito con estado "Certificado".');
      }
      // Paso 2: caché local → servidor central.
      var bytes = await readCachedActa(hito.id);
      var origen = 'caché local';
      if (bytes == null) {
        final remote = remoteActa;
        bytes = remote == null ? null : await remote(hitoId: hito.id);
        origen = 'servidor central';
      }
      if (bytes == null) {
        throw Exception(
            'El acta de conformidad aún no está disponible para este hito.');
      }
      // Paso 4: guarda la copia offline y notifica.
      final fileName = actaFileName(hito.id);
      final ubicacion = await saveActa(bytes: bytes, fileName: fileName);
      CertificationAudit.logActaDownloaded(hito: hito, ubicacion: ubicacion);
      emit(ActaDownloaded(
        fileName: fileName,
        ubicacion: ubicacion,
        origen: origen,
      ));
    } catch (e) {
      emit(ActaDownloadError(message: _message(e)));
    }
  }

  String _message(Object e) => e.toString().replaceAll('Exception: ', '');
}
