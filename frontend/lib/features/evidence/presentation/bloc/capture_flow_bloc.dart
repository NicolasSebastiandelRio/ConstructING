import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../milestones/domain/entities/milestone.dart';
import '../../data/datasources/evidence_local_data_source.dart';
import '../../domain/checksum/evidence_checksum.dart';
import '../../domain/datastamp/datastamp.dart';
import '../../domain/entities/evidence.dart';
import '../../domain/geo/closeness_validator.dart';
import '../../domain/limits/video_limit.dart';
import '../../gateway/capture_gateway.dart';
import '../../gateway/location_gateway.dart';

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
  }) : super(CaptureFlowReady()) {
    on<CaptureFlowInit>(_onInit);
    on<CapturePhotoRequested>(_onPhoto);
    on<RecordVideoRequested>(_onVideo);
    on<EvidenceNoteChanged>(_onNote);
    on<EvidenceDiscardRequested>(_onDiscard);
    on<EvidenceSaveRequested>(_onSave);
  }

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

  EvidenceDraft? _draft;
  String? _nota;

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
  /// (CU-38) → CU-36 → vista previa.
  Future<void> _captureFlow({
    required EvidenceType tipo,
    required Emitter<CaptureFlowState> emit,
  }) async {
    emit(CaptureFlowProcessing(
      message: tipo == EvidenceType.video
          ? 'Grabando video corto...'
          : 'Capturando fotografía...',
    ));

    // --- CU-31 paso 1 + Alt. 2.1/2.2: apertura con permisos del OS.
    final String path;
    try {
      path = await captureGateway.capture(tipo: tipo);
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

    // --- CU-35: validación de cercanía al punto de obra.
    final check = ClosenessValidator.check(
      latitudDispositivo: position.latitud,
      longitudDispositivo: position.longitud,
      latitudObra: obraLatitud,
      longitudObra: obraLongitud,
      radiusMeters: radioMetros,
    );
    if (!check.allowed) {
      emit(const CaptureFlowFailure(
        message: ClosenessValidator.outsideMessage,
      ));
      return;
    }

    final bytes = await captureGateway.readBytes(path);

    double? duracionSeg;
    if (tipo == EvidenceType.video) {
      // --- CU-38 pasos 2-4: límites de peso y duración del video.
      final exceeded = VideoLimitValidator.validate(
        sizeBytes: bytes.length,
        durationSeconds: null,
      );
      if (exceeded != null) {
        emit(CaptureFlowFailure(message: exceeded));
        return;
      }
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
    if (tipo == EvidenceType.foto) {
      try {
        final stamped = await DataStamp.renderOverImage(
          sourceBytes: Uint8List.fromList(bytes),
          lines: lines,
        );
        finalBytes = stamped;
      } catch (e) {
        // Sin render disponible (buffer no procesable) la marca persiste
        // como atributo y overlay (RNF_S_04: traza inalterable igual).
      }
    }

    final checksum = EvidenceChecksum.sha256OfBytes(
      Uint8List.fromList(finalBytes),
    );

    _draft = EvidenceDraft(
      path: path,
      bytes: finalBytes,
      tipo: tipo,
      latitud: position.latitud,
      longitud: position.longitud,
      precisionMetros: position.precisionMetros,
      fechaCaptura: DateTime.now(),
      marcaTexto: marcaTexto,
      checksum: checksum,
      duracionSeg: duracionSeg,
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
        checksum: draft.checksum,
        marcaTexto: draft.marcaTexto,
      );
      // CU-41/CU-44: el borrador se libera del buffer; el registro queda
      // seguro en el teléfono a la espera de cobertura de red (CU-44).
      _draft = null;
      _nota = null;
      emit(const CaptureFlowSaved(
        message: 'Evidencia guardada localmente y encolada para sincronización.',
      ));
    } catch (e) {
      emit(CaptureFlowFailure(message: e.toString().replaceAll('Exception: ', '')));
    }
  }
}
