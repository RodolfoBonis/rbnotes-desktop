import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:uuid/uuid.dart';

enum RecordingStatus { idle, recording, paused, processing }

const _systemAudioStoppedCode = 'system_audio_stopped';

/// Nota recém-criada por uma gravação (para a UI selecioná-la).
class CreatedNote {
  const CreatedNote({required this.id, required this.kind});
  final String id;
  final NoteKind kind;
}

class RecordingState extends Equatable {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.noteId,
    this.elapsed = Duration.zero,
    this.micLevel = 0,
    this.systemLevel,
    this.captureSystemAudio = false,
    this.systemAudioDropped = false,
    this.kind = NoteKind.note,
    this.liveText = '',
    this.step = 0,
    this.stepProgress = 0,
    this.error,
    this.claudeStatus,
    this.failedStep,
    this.hudDismissed = false,
  });

  final RecordingStatus status;
  final String? noteId;
  final Duration elapsed;
  final double micLevel;
  final double? systemLevel;
  final bool captureSystemAudio;
  final bool systemAudioDropped;
  final NoteKind kind;

  /// Transcrição ao vivo acumulada (HUD de gravação).
  final String liveText;

  /// Etapa atual do processamento (0..2) e seu progresso (0..1).
  final int step;
  final double stepProgress;
  final String? error;

  /// Texto do status real do resumo (SSE): fila/gerando/limite. Null fora da
  /// etapa do Claude.
  final String? claudeStatus;

  /// Etapa que falhou no processamento (0 = transcrição, 2 = resumo). Null se
  /// não houve falha. Dirige o card de erro do HUD (Tentar de novo / Fechar).
  final int? failedStep;

  /// O usuário fechou o HUD; o processamento continua em background e o
  /// progresso aparece no item da lista.
  final bool hudDismissed;

  bool get isRecording =>
      status == RecordingStatus.recording || status == RecordingStatus.paused;
  bool get isProcessing => status == RecordingStatus.processing;
  bool get isActive => status != RecordingStatus.idle;

  /// Falhou alguma etapa do processamento (mostra o card de erro no HUD).
  bool get processingFailed => failedStep != null;

  /// O HUD deve aparecer? (não, se o usuário o fechou durante o processamento).
  bool get hudVisible => isActive && !(isProcessing && hudDismissed);

  RecordingState copyWith({
    RecordingStatus? status,
    String? noteId,
    bool clearNoteId = false,
    Duration? elapsed,
    double? micLevel,
    double? systemLevel,
    bool? captureSystemAudio,
    bool? systemAudioDropped,
    NoteKind? kind,
    String? liveText,
    int? step,
    double? stepProgress,
    String? error,
    bool clearError = false,
    String? claudeStatus,
    bool clearClaudeStatus = false,
    int? failedStep,
    bool clearFailedStep = false,
    bool? hudDismissed,
  }) => RecordingState(
    status: status ?? this.status,
    noteId: clearNoteId ? null : (noteId ?? this.noteId),
    elapsed: elapsed ?? this.elapsed,
    micLevel: micLevel ?? this.micLevel,
    systemLevel: systemLevel ?? this.systemLevel,
    captureSystemAudio: captureSystemAudio ?? this.captureSystemAudio,
    systemAudioDropped: systemAudioDropped ?? this.systemAudioDropped,
    kind: kind ?? this.kind,
    liveText: liveText ?? this.liveText,
    step: step ?? this.step,
    stepProgress: stepProgress ?? this.stepProgress,
    error: clearError ? null : (error ?? this.error),
    claudeStatus: clearClaudeStatus
        ? null
        : (claudeStatus ?? this.claudeStatus),
    failedStep: clearFailedStep ? null : (failedStep ?? this.failedStep),
    hudDismissed: hudDismissed ?? this.hudDismissed,
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
    kind,
    liveText,
    step,
    stepProgress,
    error,
    claudeStatus,
    failedStep,
    hudDismissed,
  ];
}

/// Controla gravar → pausar → parar → processar, com transcrição ao vivo e as
/// três etapas do HUD de processamento (Whisper → falantes → Claude).
class RecordingCubit extends Cubit<RecordingState> {
  RecordingCubit({
    required RbNative native,
    required NoteRepository repository,
    required TranscriptionQueue queue,
    required SettingsStore settings,
    required AppPaths paths,
    required Stream<NativeDiagnostic> diagnostics,
    AiActivity? aiActivity,
    EnrichmentService? enrichment,
    Uuid? uuid,
  }) : _native = native,
       _repository = repository,
       _queue = queue,
       _settings = settings,
       _paths = paths,
       _aiActivity = aiActivity,
       _enrichment = enrichment,
       _uuid = uuid ?? const Uuid(),
       super(RecordingState(captureSystemAudio: settings.captureSystemAudio)) {
    _diagSub = diagnostics.listen(_onDiagnostic);
  }

  final RbNative _native;
  final NoteRepository _repository;
  final TranscriptionQueue _queue;
  final SettingsStore _settings;
  final AppPaths _paths;
  final AiActivity? _aiActivity;
  final EnrichmentService? _enrichment;
  final Uuid _uuid;

  StreamSubscription<AudioLevels>? _levelsSub;
  StreamSubscription<NativeDiagnostic>? _diagSub;
  StreamSubscription<LiveTranscript>? _liveSub;
  StreamSubscription<TranscriptionProgress>? _procSub;
  StreamSubscription<NoteRow?>? _aiSub;
  StreamSubscription<AiPhase>? _aiPhaseSub;
  Timer? _ticker;
  Timer? _stepTicker;
  DateTime? _startedAt;
  Duration _accumulated = Duration.zero;

  final _created = StreamController<CreatedNote>.broadcast();

  /// Notas recém-criadas (a lista seleciona a nota ao surgir).
  Stream<CreatedNote> get createdNotes => _created.stream;

  void setCaptureSystemAudio({required bool value}) {
    if (state.isActive) return;
    emit(state.copyWith(captureSystemAudio: value));
  }

  /// Inicia uma gravação de nota.
  Future<void> start({NoteKind kind = NoteKind.note}) async {
    if (state.isActive) return;
    emit(state.copyWith(clearError: true, kind: kind));

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
          folderId: Value(kind == NoteKind.diary ? 'diario' : null),
          kind: Value(kind),
        ),
      );
      await _native.startRecording(
        id: id,
        directory: _paths.recordingsDir,
        captureSystemAudio: state.captureSystemAudio,
        liveTranscription: true,
        inputDeviceId: _settings.micDeviceId,
      );
      _startedAt = now;
      _accumulated = Duration.zero;
      _listenLevels(id);
      _listenLive(id);
      _startTicker();
      emit(
        state.copyWith(
          status: RecordingStatus.recording,
          noteId: id,
          elapsed: Duration.zero,
          liveText: '',
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

  /// Inicia uma gravação de diário.
  Future<void> startDiary() => start(kind: NoteKind.diary);

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

  /// Conclui: finaliza a gravação, enfileira a transcrição e mostra o HUD de
  /// processamento (3 etapas) até a IA terminar.
  Future<void> stop() async {
    if (!state.isRecording) return;
    final id = state.noteId!;
    _ticker?.cancel();
    await _levelsSub?.cancel();
    await _liveSub?.cancel();
    try {
      final result = await _native.stopRecording(id);
      await _repository.finalizeRecording(
        id,
        durationMs: result.duration.inMilliseconds,
        playbackPath: result.playbackPath,
        micWavPath: result.micWavPath,
        systemWavPath: result.systemWavPath,
      );
      emit(
        state.copyWith(
          status: RecordingStatus.processing,
          step: 0,
          stepProgress: 0,
        ),
      );
      _startProcessing(id);
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
      _reset();
    }
  }

  /// Descarta a gravação em andamento (apaga a nota).
  Future<void> discard() async {
    final id = state.noteId;
    _ticker?.cancel();
    await _levelsSub?.cancel();
    await _liveSub?.cancel();
    if (id != null) {
      try {
        await _native.stopRecording(id);
      } on Object catch (_) {
        // já parado; ignore.
      }
      await _repository.deleteNote(id);
    }
    _reset();
  }

  // ---------- processamento ----------

  void _startProcessing(String noteId) {
    unawaited(_procSub?.cancel());
    _procSub = _queue.progress.where((p) => p.noteId == noteId).listen((p) {
      if (p.done) {
        // Etapa 0 (Whisper) concluída → etapa 1 (falantes/pontuação).
        emit(state.copyWith(step: 1, stepProgress: 0));
        _advanceToClaude(noteId);
      } else if (!p.isTerminal) {
        emit(state.copyWith(step: 0, stepProgress: p.progress));
      } else if (p.failed) {
        // Falha de transcrição: mostra o estado de erro no HUD (não encerra),
        // com "Tentar de novo" e "Fechar".
        emit(
          state.copyWith(
            step: 0,
            failedStep: 0,
            error: 'Não foi possível transcrever.',
          ),
        );
      } else {
        // Cancelamento: encerra o HUD silenciosamente.
        _finishProcessing(noteId);
      }
    });
  }

  void _advanceToClaude(String noteId) {
    // Etapa 1 é rápida (merge já aconteceu); animação curta e vai p/ Claude.
    _stepTicker?.cancel();
    emit(state.copyWith(step: 1, stepProgress: 0.6));
    Timer(const Duration(milliseconds: 300), () {
      if (isClosed) return;
      emit(state.copyWith(step: 2, stepProgress: 0.05));
      _tickClaude();
      unawaited(_aiSub?.cancel());
      _listenClaudePhase();
      _aiSub = _repository.watchNote(noteId).listen((note) {
        if (note == null) return;
        if (note.aiStatus == AiStatus.failed) {
          _stepTicker?.cancel();
          emit(
            state.copyWith(
              step: 2,
              failedStep: 2,
              error: 'Não foi possível gerar o resumo.',
            ),
          );
        } else if (note.aiStatus == AiStatus.ready ||
            note.aiStatus == AiStatus.none) {
          _finishProcessing(noteId);
        }
      });
    });
  }

  /// Reflete a fase real do resumo (SSE) no texto da etapa do Claude.
  void _listenClaudePhase() {
    final activity = _aiActivity;
    if (activity == null) return;
    unawaited(_aiPhaseSub?.cancel());
    _aiPhaseSub = activity.stream.listen((phase) {
      final text = switch (phase) {
        AiPhase.queued => 'Na fila…',
        AiPhase.streaming => 'Gerando…',
        AiPhase.dailyLimit => 'Limite diário atingido',
        AiPhase.error => 'Erro no resumo',
        AiPhase.idle => null,
      };
      emit(state.copyWith(claudeStatus: text, clearClaudeStatus: text == null));
    });
  }

  /// "Tentar de novo" no HUD de erro: reexecuta a etapa que falhou.
  Future<void> retryProcessing() async {
    final noteId = state.noteId;
    if (noteId == null || state.failedStep == null) return;
    final failed = state.failedStep!;
    emit(
      state.copyWith(
        clearError: true,
        clearFailedStep: true,
        stepProgress: 0,
        step: failed,
      ),
    );
    if (failed == 0) {
      await _repository.setStatus(noteId, NoteStatus.transcribing);
      _queue.retry(noteId);
    } else {
      _tickClaude();
      await _enrichment?.enrichNote(noteId, force: true);
    }
  }

  /// Fecha o HUD. Se o processamento ainda roda, ele continua em background e o
  /// progresso aparece no item da lista; se falhou, apenas abandona o HUD.
  void closeHud() {
    if (state.processingFailed) {
      _finishProcessing(state.noteId ?? '');
    } else {
      emit(state.copyWith(hudDismissed: true));
    }
  }

  void _tickClaude() {
    _stepTicker?.cancel();
    _stepTicker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (isClosed) return;
      final next = (state.stepProgress + 0.04).clamp(0.0, 0.95);
      emit(state.copyWith(stepProgress: next));
    });
  }

  void _finishProcessing(String noteId) {
    _stepTicker?.cancel();
    unawaited(_procSub?.cancel());
    unawaited(_aiSub?.cancel());
    unawaited(_aiPhaseSub?.cancel());
    if (noteId.isNotEmpty) {
      _created.add(CreatedNote(id: noteId, kind: state.kind));
    }
    _reset();
  }

  void _onDiagnostic(NativeDiagnostic diagnostic) {
    if (diagnostic.code == _systemAudioStoppedCode && state.isRecording) {
      emit(state.copyWith(systemAudioDropped: true));
    }
  }

  void _listenLevels(String id) {
    unawaited(_levelsSub?.cancel());
    _levelsSub = _native.audioLevels(id).listen((levels) {
      emit(state.copyWith(micLevel: levels.mic, systemLevel: levels.system));
    });
  }

  void _listenLive(String id) {
    unawaited(_liveSub?.cancel());
    _liveSub = _native.liveTranscript(id).listen((t) {
      if (!t.isFinal) emit(state.copyWith(liveText: t.text));
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
    _stepTicker?.cancel();
    _startedAt = null;
    _accumulated = Duration.zero;
    emit(RecordingState(captureSystemAudio: _settings.captureSystemAudio));
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
    _stepTicker?.cancel();
    await _levelsSub?.cancel();
    await _liveSub?.cancel();
    await _procSub?.cancel();
    await _aiSub?.cancel();
    await _aiPhaseSub?.cancel();
    await _diagSub?.cancel();
    await _created.close();
    return super.close();
  }
}
