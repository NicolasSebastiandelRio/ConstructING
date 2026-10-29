import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../audit/data/audit_log_writer.dart';
import '../../../milestones/domain/entities/milestone.dart';
import '../../../notifications/data/notification_dispatcher.dart';
import '../../data/datasources/evidence_local_data_source.dart';
import '../../domain/checksum/evidence_checksum.dart';
import '../../domain/crypto/evidence_hash_service.dart';
import '../../domain/datastamp/datastamp.dart';
import '../../domain/editing/evidence_edit_ops.dart';
import '../../domain/entities/evidence.dart';
import '../../domain/geo/closeness_validator.dart';
import '../../domain/limits/video_limit.dart';
import '../../domain/validation/evidence_file_validator.dart';
import '../../gateway/capture_gateway.dart';
import '../../gateway/location_gateway.dart';
import '../../gateway/video_duration.dart';

/// Borrador de evidencia en memoria temporal (CU-41: buffer RAM). Se
/// confirma con "Guardar" (CU-42) o se descarta sin persistir (CU-41).
class EvidenceDraft extends Equatable {
  final String path;
  final List<int> bytes;
  final EvidenceType tipo;
  final double latitud;
  final double longitud;
  final double precisionMetros;
  final DateTime fechaCaptura;
  final String marcaTexto;
  final String checksum;
  final double? duracionSeg;

  /// CU-35 soft-fail: la captura no coincide con el ancla de la obra
  /// (fuera del radio o sin ancla comparable). La evidencia se guarda
  /// igual y la UI estampa la etiqueta roja de no coincidencia.
  final bool fueraDeObra;

  const EvidenceDraft({
    required this.path,
    required this.bytes,
    required this.tipo,
    required this.latitud,
    required this.longitud,
    required this.precisionMetros,
    required this.fechaCaptura,
    required this.marcaTexto,
    required this.checksum,
    this.duracionSeg,
    this.fueraDeObra = false,
  });

  @override
  List<Object?> get props => [
        path,
        tipo,
        latitud,
        longitud,
        precisionMetros,
        fechaCaptura,
        marcaTexto,
        checksum,
        duracionSeg,
        fueraDeObra,
      ];
}

abstract class CaptureFlowState extends Equatable {
  const CaptureFlowState();

  @override
  List<Object?> get props => [];
}

/// CU-31 pasos 1-2: solicitando apertura de cámara al SO.
class CaptureFlowInitializing extends CaptureFlowState {}

/// CU-31 paso 4: interfaz de captura activa y a la escucha.
class CaptureFlowReady extends CaptureFlowState {}

/// CU-32 pasos 2-4 / CU-33 pasos 2-4: capturando y procesando.
class CaptureFlowProcessing extends CaptureFlowState {
  final String message;

  const CaptureFlowProcessing({this.message = 'Procesando evidencia...'});

  @override
  List<Object?> get props => [message];
}

/// CU-32 paso 4 / CU-33 paso 3: vista previa con marca estampada.
class CaptureFlowPreview extends CaptureFlowState {
  final EvidenceDraft draft;

  const CaptureFlowPreview({required this.draft});

  @override
  List<Object?> get props => [draft];
}

/// Guardado confirmado (CU-42 + encolado CU-44): poscondición cumplida.
class CaptureFlowSaved extends CaptureFlowState {
  final String message;

  const CaptureFlowSaved({required this.message});

  @override
  List<Object?> get props => [message];
}

/// Fallo con alerta visual para el usuario (Alt. de CU-31/32/33/34/35/38).
class CaptureFlowFailure extends CaptureFlowState {
  final String message;

  const CaptureFlowFailure({required this.message});

  @override
  List<Object?> get props => [message];
}

abstract class CaptureFlowEvent extends Equatable {
  const CaptureFlowEvent();

  @override
  List<Object?> get props => [];
}

/// CU-31 paso 1: solicita apertura de cámara (verificación de permisos).
class CaptureFlowInit extends CaptureFlowEvent {}

/// CU-32 paso 1: encuadra el avance y presiona el obturador.
class CapturePhotoRequested extends CaptureFlowEvent {}

/// RF_03 (ajuste post-MVP): el usuario ELIGE una imagen existente del
/// dispositivo en lugar de tomarla en vivo.
///
/// La fuente queda registrada en la auditoría (`origen=galeria`) para no
/// perder la trazabilidad pericial que aportaba el CU-37.
class PickPhotoFromGalleryRequested extends CaptureFlowEvent {}

/// CU-33 paso 1: inicia la grabación del video corto.
class RecordVideoRequested extends CaptureFlowEvent {}

/// CU-39 pasos 1-3: vincula la observación técnica al borrador.
class EvidenceNoteChanged extends CaptureFlowEvent {
  final String nota;

  const EvidenceNoteChanged({required this.nota});

  @override
  List<Object?> get props => [nota];
}

/// CU-41 paso 1: descarta y vuelve a la vista en vivo.
class EvidenceDiscardRequested extends CaptureFlowEvent {}

/// CU-32 paso 5 / CU-33 paso 3: confirma el guardado ("Guardar").
class EvidenceSaveRequested extends CaptureFlowEvent {}

/// Bloc del flujo de captura de evidencia (CU-31..CU-42, RF_03/RF_04).
class CaptureFlowBloc extends Bloc<CaptureFlowEvent, CaptureFlowState> {
  CaptureFlowBloc({
    required this.captureGateway,
    required this.locationGateway,
    required this.evidences,
    required this.hito,
    required this.obraId,
    this.obraLatitud,
    this.obraLongitud,
    this.radioMetros = ClosenessValidator.defaultRadiusMeters,
    this.videoDurationReader = readVideoDuration,
    required this.auditLog,
    this.hashService = const EvidenceHashService(),
    this.notificationDispatcher,
    this.propietarioDeObra,
    this.obraNombre,
    this.editImage,
    this.pickFromGallery,
  }) : super(CaptureFlowReady()) {
    on<CaptureFlowInit>(_onInit);
    on<CapturePhotoRequested>(_onPhoto);
    on<PickPhotoFromGalleryRequested>(_onPickFromGallery);
    on<RecordVideoRequested>(_onVideo);
    on<EvidenceNoteChanged>(_onNote);
    on<EvidenceDiscardRequested>(_onDiscard);
    on<EvidenceSaveRequested>(_onSave);
  }

  /// CU-60 (RF_08): huella imborrable de la carga de evidencia. Obligatorio
  /// en producción (DI): la huella no es omitible — cada transacción
  /// crítica genera su fila en la tabla inmutable de auditoría.
  final AuditLogWriter auditLog;

  /// CU-58 (RF_08/RNF_S_03): Motor Criptográfico invocado durante el
  /// almacenamiento (paso 2). Inyectable en tests; producción usa el motor
  /// real (SHA-256 sobre el binario en memoria).
  final EvidenceHashService hashService;

  /// CU-67 (RF_10): motor de alertas. Al subir una foto el módulo de hitos
  /// emite la señal de "Actualización de Obra" al Propietario (paso 1).
  /// Opcional: sin él el guardado local sigue igual (best-effort).
  final NotificationDispatcher? notificationDispatcher;

  /// CU-67 paso 1: resuelve el `ID del Propietario` de la obra. Inyectable en
  /// tests; en producción lo provee el módulo de obras.
  final Future<String?> Function(String obraId)? propietarioDeObra;

  /// Nombre de la obra para el cuerpo de la alerta (CU-67 paso 4).
  final String? obraNombre;

  /// RF_03 (ajuste post-MVP): hook de edición de la fotografía. Recibe los
  /// bytes recién capturados y devuelve los editados (recorte/giro) o `null`
  /// si el usuario canceló. Se aplica ANTES de estampar la marca pericial
  /// (CU-36), así la evidencia y su checksum corresponden al encuadre final.
  /// Inyectable: en tests se omite (sin edición).
  final Future<List<int>?> Function(List<int> bytes)? editImage;

  /// RF_03: selector de imagen existente del dispositivo (galería). Su
  /// resultado se registra como `origen=galeria` en la auditoría.
  /// Inyectable en tests; en producción usa `LiveCaptureGateway`.
  final Future<String> Function()? pickFromGallery;

  final CaptureGateway captureGateway;
  final LocationGateway locationGateway;
  final EvidenceLocalDataSource evidences;

  /// Hito al que se vincula la evidencia (precondición CU-40 afín).
  final Milestone hito;
  final String obraId;

  /// Coordenadas ancla de la obra (CU-15) para el CU-35.
  final double? obraLatitud;
  final double? obraLongitud;
  final double radioMetros;

  /// CU-38 paso 2: lector de la duración real del video (metadato).
  /// Inyectable en tests; producción usa `video_player`.
  final VideoDurationReader videoDurationReader;

  EvidenceDraft? _draft;
  String? _nota;

  /// RF_03 (ajuste post-MVP): origen de la imagen (`camara` o `galeria`).
  /// Queda anotado en la huella del CU-60 para conservar la trazabilidad
  /// pericial que aportaba el CU-37 (captura en vivo).
  String _origen = 'camara';

  Future<void> _onInit(
    CaptureFlowInit event,
    Emitter<CaptureFlowState> emit,
  ) async {
    // CU-31 paso 2: el entorno de cámara aislado (CU-37) se valida al
    // primer uso; la interfaz queda lista y a la escucha (paso 4).
    emit(CaptureFlowReady());
  }

  /// CU-32: captura del fotograma del avance.
  Future<void> _onPhoto(
    CapturePhotoRequested event,
    Emitter<CaptureFlowState> emit,
  ) async {
    await _captureFlow(
      tipo: EvidenceType.foto,
      emit: emit,
    );
  }

  /// RF_03 (ajuste post-MVP): el usuario elige una imagen ya existente.
  Future<void> _onPickFromGallery(
    PickPhotoFromGalleryRequested event,
    Emitter<CaptureFlowState> emit,
  ) async {
    await _captureFlow(
      tipo: EvidenceType.foto,
      emit: emit,
      fromGallery: true,
    );
  }

  /// CU-33: grabación del video corto de evidencia.
  Future<void> _onVideo(
    RecordVideoRequested event,
    Emitter<CaptureFlowState> emit,
  ) async {
    await _captureFlow(
      tipo: EvidenceType.video,
      emit: emit,
    );
  }

  /// Flujo común CU-32/CU-33 (pasos 2-4): captura → CU-34 → CU-35 →
  /// (CU-38) → [edición RF_03] → CU-36 → vista previa.
  Future<void> _captureFlow({
    required EvidenceType tipo,
    required Emitter<CaptureFlowState> emit,
    bool fromGallery = false,
  }) async {
    emit(CaptureFlowProcessing(
      message: tipo == EvidenceType.video
          ? 'Grabando video corto...'
          : (fromGallery
              ? 'Seleccionando imagen del dispositivo...'
              : 'Capturando fotografía...'),
    ));
    _origen = fromGallery ? 'galeria' : 'camara';

    // --- CU-31 paso 1 + Alt. 2.1/2.2: apertura con permisos del OS, o
    // selector de imagen existente (RF_03 post-MVP).
    final String path;
    try {
      final selector = pickFromGallery;
      if (fromGallery && selector != null) {
        path = await selector();
      } else {
        path = await captureGateway.capture(tipo: tipo);
      }
    } on CameraPermissionException catch (e) {
      emit(CaptureFlowFailure(message: e.message));
      return;
    } catch (e) {
      emit(const CaptureFlowFailure(
        message: 'No se pudo inicializar la cámara del dispositivo.',
      ));
      return;
    }

    // --- CU-32 paso 2 / CU-33 paso 2: obtención de la ubicación (CU-34).
    final position = await _obtainPosition(emit);
    if (position == null) return; // Alt. CU-34: abortó con mensaje.

    // --- CU-35: validación de cercanía al punto de obra (soft-fail,
    // Sprint 4): fuera del radio o sin ancla NO aborta más la captura; la
    // evidencia queda marcada y la UI estampa la etiqueta roja permanente.
    final check = ClosenessValidator.check(
      latitudDispositivo: position.latitud,
      longitudDispositivo: position.longitud,
      latitudObra: obraLatitud,
      longitudObra: obraLongitud,
      radiusMeters: radioMetros,
    );
    final fueraDeObra = !check.allowed;

    // --- Lectura del binario con manejo de error explícito: un archivo
    // inaccesible (permiso revocado, blob del navegador liberado) no debe
    // tumbar el flujo de captura.
    List<int> bytes;
    try {
      bytes = await captureGateway.readBytes(path);
    } catch (_) {
      emit(const CaptureFlowFailure(
        message: 'No se pudo leer el archivo seleccionado.',
      ));
      return;
    }

    // --- RF_03: la evidencia final siempre es JPG/JPEG. En vez de rechazar
    // otros formatos (las capturas de pantalla del celular son PNG) la imagen
    // se CONVIERTE automáticamente a JPEG, que es lo que espera el resto del
    // pipeline y el backend. Solo se rechaza lo que no es una imagen.
    if (tipo == EvidenceType.foto) {
      final rechazo = EvidenceFileValidator.rechazo(bytes, path: path);
      if (rechazo != null) {
        emit(CaptureFlowFailure(message: rechazo));
        return;
      }
      if (!EvidenceFileValidator.esJpeg(bytes)) {
        emit(const CaptureFlowProcessing(
            message: 'Convirtiendo la imagen a JPG...'));
        final convertida =
            EvidenceEditOps.rotate(Uint8List.fromList(bytes), 0);
        if (convertida == null) {
          emit(const CaptureFlowFailure(
              message: EvidenceFileValidator.notImageMessage));
          return;
        }
        bytes = convertida.bytes;
      }
    }

    double? duracionSeg;
    if (tipo == EvidenceType.video) {
      // --- CU-38 pasos 2-4: límites de peso y duración del video. La
      // duración ahora se LEE del metadato real (antes se validaba con
      // null: el límite de duración no se aplicaba nunca y `duracionSeg`
      // nunca se persistía). En video el archivo definitivo es el mismo
      // temporal del picker (no se re-estampa), por eso aquí no hay
      // divergencia posible con el checksum.
      duracionSeg = await videoDurationReader(path);
      final exceeded = VideoLimitValidator.validate(
        sizeBytes: bytes.length,
        durationSeconds: duracionSeg,
      );
      if (exceeded != null) {
        emit(CaptureFlowFailure(message: exceeded));
        return;
      }
    }

    // --- RF_03 (ajuste post-MVP): recorte/giro de la fotografía ANTES de
    // estampar la marca pericial (CU-36). Así la evidencia persistida, su
    // checksum (CU-58) y la marca corresponden al encuadre elegido por el
    // usuario, y la marca nunca queda fuera del recorte.
    if (tipo == EvidenceType.foto && editImage != null) {
      emit(const CaptureFlowProcessing(message: 'Editando la imagen...'));
      List<int>? editada;
      try {
        editada = await editImage!(bytes);
      } catch (_) {
        // El editor/recorte falló (imagen no procesable): se informa sin
        // dejar el flujo en un estado inconsistente.
        emit(const CaptureFlowFailure(
          message: 'No se pudo procesar la imagen. Intente con otra foto.',
        ));
        return;
      }
      if (editada == null) {
        // Canceló la edición: se vuelve al entorno de captura sin generar
        // archivos ni registros (CU-41).
        emit(CaptureFlowReady());
        return;
      }
      if (editada.isNotEmpty) bytes = editada;
    }

    // --- CU-36: estampa de marca de agua inalterable (RNF_S_04).
    final lines = DataStamp.buildLines(
      fechaCaptura: DateTime.now(),
      latitud: position.latitud,
      longitud: position.longitud,
      precisionMetros: position.precisionMetros,
      hitoNombre: hito.nombre,
      nota: _nota,
    );
    final marcaTexto = DataStamp.composeText(lines);
    List<int> finalBytes = bytes;
    String archivoDefinitivo = path;
    if (tipo == EvidenceType.foto) {
      try {
        final stamped = await DataStamp.renderOverImage(
          sourceBytes: Uint8List.fromList(bytes),
          lines: lines,
        );
        finalBytes = stamped;
        // Sprint 4 (CU-45): persiste los bytes ESTAMPADOS como archivo del
        // caché local. El checksum se calcula sobre estos bytes; si se
        // sincronizara el temporal del picker (sin marca) el servidor
        // detectaría divergencia y la evidencia nunca saldría pendiente.
        archivoDefinitivo = await captureGateway.persistFinal(
          stamped,
          originalPath: path,
        );
      } catch (e) {
        // Sin render disponible (buffer no procesable) la marca persiste
        // como atributo y overlay (RNF_S_04: traza inalterable igual); el
        // checksum queda descripto por el archivo original (coherente).
      }
    }

    final checksum = EvidenceChecksum.sha256OfBytes(
      Uint8List.fromList(finalBytes),
    );

    _draft = EvidenceDraft(
      path: archivoDefinitivo,
      bytes: finalBytes,
      tipo: tipo,
      latitud: position.latitud,
      longitud: position.longitud,
      precisionMetros: position.precisionMetros,
      fechaCaptura: DateTime.now(),
      marcaTexto: marcaTexto,
      checksum: checksum,
      duracionSeg: duracionSeg,
      fueraDeObra: fueraDeObra,
    );
    emit(CaptureFlowPreview(draft: _draft!));
  }

  /// CU-34 (pasos 1-4): posición actual con timeout 5 s. Ante fallo
  /// (Alt. 4.1/4.2) emite la falla y aborta la captura (retorna null).
  Future<DevicePosition?> _obtainPosition(
    Emitter<CaptureFlowState> emit,
  ) async {
    try {
      return await locationGateway.getCurrentPosition();
    } on GeolocationException catch (e) {
      emit(CaptureFlowFailure(message: e.message));
      return null;
    } catch (e) {
      emit(const CaptureFlowFailure(
        message: 'No se pudo obtener la ubicación del dispositivo.',
      ));
      return null;
    }
  }

  /// CU-39 pasos 1-4: vincula el texto como atributo del borrador en
  /// memoria temporal.
  void _onNote(
    EvidenceNoteChanged event,
    Emitter<CaptureFlowState> emit,
  ) {
    _nota = event.nota.trim().isEmpty ? null : event.nota.trim();
    final draft = _draft;
    if (draft != null) {
      _draft = EvidenceDraft(
        path: draft.path,
        bytes: draft.bytes,
        tipo: draft.tipo,
        latitud: draft.latitud,
        longitud: draft.longitud,
        precisionMetros: draft.precisionMetros,
        fechaCaptura: draft.fechaCaptura,
        marcaTexto: draft.marcaTexto,
        checksum: draft.checksum,
        duracionSeg: draft.duracionSeg,
        fueraDeObra: draft.fueraDeObra,
      );
    }
    emit(state);
  }

  /// CU-41 pasos 1-4: descarta el borrador (buffer RAM liberado) y retorna
  /// a la vista en vivo para un nuevo intento.
  void _onDiscard(
    EvidenceDiscardRequested event,
    Emitter<CaptureFlowState> emit,
  ) {
    _draft = null;
    emit(CaptureFlowReady());
  }

  /// CU-32 pasos 5-6 / CU-33 paso 4: confirma el guardado; CU-42 persiste
  /// el registro con `es_sincronizado=false` y queda encolado para el
  /// CU-44. RNF_C_02: la escritura es transaccional con alerta inmediata.
  Future<void> _onSave(
    EvidenceSaveRequested event,
    Emitter<CaptureFlowState> emit,
  ) async {
    final draft = _draft;
    if (draft == null) {
      emit(const CaptureFlowFailure(message: 'No hay evidencia para guardar.'));
      return;
    }
    emit(const CaptureFlowProcessing(message: 'Guardando en el caché local...'));
    try {
      // CU-58 pasos 2+4: el Motor Criptográfico firma el binario en memoria
      // durante el almacenamiento y el hash queda asociado al registro.
      final hash = await hashService.hashBytes(
        Uint8List.fromList(draft.bytes),
      );
      await evidences.create(
        hitoId: hito.id,
        obraId: obraId,
        tipo: draft.tipo,
        archivo: draft.path,
        nota: _nota,
        latitud: draft.latitud,
        longitud: draft.longitud,
        precisionMetros: draft.precisionMetros,
        fechaCaptura: draft.fechaCaptura,
        duracionSeg: draft.duracionSeg,
        tamanoBytes: draft.bytes.length,
        checksum: hash,
        marcaTexto: draft.marcaTexto,
        fueraDeObra: draft.fueraDeObra,
      );
      // CU-41/CU-44: el borrador se libera del buffer; el registro queda
      // seguro en el teléfono a la espera de cobertura de red (CU-44).
      _draft = null;
      _nota = null;
      // CU-60: huella de la transacción crítica, con las coordenadas
      // actuales de la captura (RF_08, RNF_S_03). Obligatorio: la huella
      // no es omitible.
      await auditLog.log(
        accion: 'evidencia_cargada',
        detalle:
            'tipo=${draft.tipo.label} checksum=${hash.toLowerCase()} origen=$_origen',
        obraId: obraId,
        coordenadas: '${draft.latitud},${draft.longitud}',
      );
      // CU-67: señal de "Actualización de Obra" al Propietario (best-effort:
      // nunca revierte el guardado, que ya es transaccional).
      await _notificarAvanceAlPropietario(draft.tipo.label);
      emit(CaptureFlowSaved(
        message: draft.fueraDeObra
            ? 'Evidencia guardada. Su ubicación no coincide con la obra: '
                'quedará etiquetada en rojo en la galería.'
            : 'Evidencia guardada localmente y encolada para sincronización.',
      ));
    } catch (e) {
      emit(CaptureFlowFailure(message: e.toString().replaceAll('Exception: ', '')));
    }
  }

  /// CU-67 (RF_10): el módulo de hitos emite la señal de "Actualización de
  /// Obra" con el `ID del Propietario` tras subir la evidencia; el motor de
  /// notificaciones aplica las preferencias del receptor (CU-71) y despacha.
  ///
  /// Best-effort: la evidencia ya quedó persistida de forma transaccional, así
  /// que un fallo de la alerta se traza y no revierte nada.
  Future<void> _notificarAvanceAlPropietario(String tipoEvidencia) async {
    final dispatcher = notificationDispatcher;
    final resolver = propietarioDeObra;
    if (dispatcher == null || resolver == null) return;
    try {
      final propietarioId = await resolver(obraId);
      if (propietarioId == null || propietarioId.trim().isEmpty) return;
      await dispatcher.notifyAvanceDeObra(
        propietarioId: propietarioId,
        obraId: obraId,
        obraNombre: obraNombre ?? obraId,
        hitoNombre: hito.nombre,
        causa: 'evidencia de $tipoEvidencia cargada',
        hitoId: hito.id,
      );
    } catch (e) {
      debugPrint('CU-67: alerta de avance pendiente (obra $obraId): $e');
    }
  }
}
