import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:uuid/uuid.dart';

enum RecordingStatus { idle, recording, paused }

/// Diagnóstico nativo: o áudio do sistema caiu durante a gravação.
const _systemAudioStoppedCode = 'system_audio_stopped';

class RecordingState extends Equatable {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.noteId,
    this.elapsed = Duration.zero,
    this.micLevel = 0,
    this.systemLevel,
    this.captureSystemAudio = false,
    this.systemAudioDropped = false,
    this.error,
  });

  final RecordingStatus status;
  final String? noteId;
  final Duration elapsed;
  final double micLevel;
  final double? systemLevel;
  final bool captureSystemAudio;

  /// O áudio do sistema caiu no meio da gravação (SCStream parou). O mic segue.
  final bool systemAudioDropped;
  final String? error;

  bool get isActive => status != RecordingStatus.idle;

  RecordingState copyWith({
    RecordingStatus? status,
    String? noteId,
    Duration? elapsed,
    double? micLevel,
    double? systemLevel,
    bool? captureSystemAudio,
    bool? systemAudioDropped,
    String? error,
    bool clearError = false,
  }) => RecordingState(
    status: status ?? this.status,
    noteId: noteId ?? this.noteId,
    elapsed: elapsed ?? this.elapsed,
    micLevel: micLevel ?? this.micLevel,
    systemLevel: systemLevel ?? this.systemLevel,
    captureSystemAudio: captureSystemAudio ?? this.captureSystemAudio,
    systemAudioDropped: systemAudioDropped ?? this.systemAudioDropped,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    status,
    noteId,
    elapsed,
    micLevel,
    systemLevel,
    captureSystemAudio,
    systemAudioDropped,
    error,
  ];
}

/// Controla o ciclo gravar → pausar → parar e cria a nota ao encerrar.
class RecordingCubit extends Cubit<RecordingState> {
  RecordingCubit({
    required RbNative native,
    required NoteRepository repository,
    required TranscriptionQueue queue,
    required SettingsStore settings,
    required AppPaths paths,
    required Stream<NativeDiagnostic> diagnostics,
    Uuid? uuid,
  }) : _native = native,
       _repository = repository,
       _queue = queue,
       _settings = settings,
       _paths = paths,
       _uuid = uuid ?? const Uuid(),
       super(
         RecordingState(captureSystemAudio: settings.captureSystemAudio),
       ) {
    _diagSub = diagnostics.listen(_onDiagnostic);
  }

  final RbNative _native;
  final NoteRepository _repository;
  final TranscriptionQueue _queue;
  final SettingsStore _settings;
  final AppPaths _paths;
  final Uuid _uuid;

  StreamSubscription<AudioLevels>? _levelsSub;
  StreamSubscription<NativeDiagnostic>? _diagSub;
  Timer? _ticker;
  DateTime? _startedAt;
  Duration _accumulated = Duration.zero;

  void setCaptureSystemAudio({required bool value}) {
    if (state.isActive) return;
    emit(state.copyWith(captureSystemAudio: value));
  }

  Future<void> start() async {
    if (state.isActive) return;
    emit(state.copyWith(clearError: true));

    final mic = await _native.permissionStatus(RbPermission.microphone);
    if (mic != PermissionStatus.granted) {
      final result = await _native.requestPermission(RbPermission.microphone);
      if (result != PermissionStatus.granted) {
        emit(state.copyWith(error: 'Permissão de microfone necessária.'));
        return;
      }
    }

    final id = _uuid.v4();
    final now = DateTime.now();
    try {
      await _repository.insertNote(
        NotesCompanion.insert(
          id: id,
          createdAt: now,
          updatedAt: now,
          status: NoteStatus.recording,
          source: NoteSource.recording,
        ),
      );
      await _native.startRecording(
        id: id,
        directory: _paths.recordingsDir,
        captureSystemAudio: state.captureSystemAudio,
      );
      _startedAt = now;
      _accumulated = Duration.zero;
      _listenLevels(id);
      _startTicker();
      emit(
        state.copyWith(
          status: RecordingStatus.recording,
          noteId: id,
          elapsed: Duration.zero,
          systemAudioDropped: false,
        ),
      );
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'start_recording',
        category: 'recording',
      );
      await _repository.deleteNote(id);
      emit(state.copyWith(error: _messageFor(e)));
    }
  }

  Future<void> pause() async {
    if (state.status != RecordingStatus.recording) return;
    final id = state.noteId!;
    try {
      await _native.pauseRecording(id);
      _accumulated += DateTime.now().difference(_startedAt!);
      _ticker?.cancel();
      await _levelsSub?.cancel();
      emit(state.copyWith(status: RecordingStatus.paused, micLevel: 0));
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'pause_recording',
        category: 'recording',
      );
    }
  }

  Future<void> resume() async {
    if (state.status != RecordingStatus.paused) return;
    final id = state.noteId!;
    try {
      await _native.resumeRecording(id);
      _startedAt = DateTime.now();
      _listenLevels(id);
      _startTicker();
      emit(state.copyWith(status: RecordingStatus.recording));
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'resume_recording',
        category: 'recording',
      );
    }
  }

  Future<void> stop() async {
    if (!state.isActive) return;
    final id = state.noteId!;
    _ticker?.cancel();
    await _levelsSub?.cancel();
    try {
      final result = await _native.stopRecording(id);
      await _repository.finalizeRecording(
        id,
        durationMs: result.duration.inMilliseconds,
        playbackPath: result.playbackPath,
        micWavPath: result.micWavPath,
        systemWavPath: result.systemWavPath,
      );
      _queue.enqueue(id);
    } on RbNativeException catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'stop_recording',
        category: 'recording',
      );
      await _repository.setStatus(id, NoteStatus.failed);
      emit(state.copyWith(error: _messageFor(e)));
    } finally {
      _reset();
    }
  }

  void _onDiagnostic(NativeDiagnostic diagnostic) {
    if (diagnostic.code == _systemAudioStoppedCode && state.isActive) {
      emit(state.copyWith(systemAudioDropped: true));
    }
  }

  void _listenLevels(String id) {
    unawaited(_levelsSub?.cancel());
    _levelsSub = _native.audioLevels(id).listen((levels) {
      emit(state.copyWith(micLevel: levels.mic, systemLevel: levels.system));
    });
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final current =
          _accumulated +
          DateTime.now().difference(_startedAt ?? DateTime.now());
      emit(state.copyWith(elapsed: current));
    });
  }

  void _reset() {
    _ticker?.cancel();
    _startedAt = null;
    _accumulated = Duration.zero;
    emit(
      RecordingState(captureSystemAudio: _settings.captureSystemAudio),
    );
  }

  String _messageFor(RbNativeException e) => switch (e.code) {
    RbNativeErrorCode.alreadyRecording =>
      'Já existe uma gravação em andamento.',
    RbNativeErrorCode.permissionDenied => 'Permissão negada.',
    _ => 'Falha na gravação (${e.code}).',
  };

  @override
  Future<void> close() async {
    _ticker?.cancel();
    await _levelsSub?.cancel();
    await _diagSub?.cancel();
    return super.close();
  }
}
