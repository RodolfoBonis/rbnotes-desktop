import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:rbnotes/native/rb_native.dart';

/// Implementação em memória do contrato nativo para desenvolvimento e testes.
///
/// Gera arquivos-placeholder reais em disco (para o player e a recuperação
/// funcionarem) e segmentos de transcrição canônicos com palavras e
/// confiança. Todo comportamento é configurável para os testes não dependerem
/// de temporizadores reais.
class FakeRbNative implements RbNative {
  FakeRbNative({
    Map<RbPermission, PermissionStatus>? permissions,
    this.modelDownloaded = true,
    List<TranscriptSegment>? transcriptResult,
    this.systemAudioAvailable = true,
    this.levelsInterval = const Duration(milliseconds: 50),
  }) : _permissions = {
         RbPermission.microphone: PermissionStatus.granted,
         RbPermission.screenRecording: PermissionStatus.granted,
         RbPermission.accessibility: PermissionStatus.granted,
         ...?permissions,
       },
       _transcriptResult = transcriptResult ?? _defaultSegments;

  static List<TranscriptSegment> get _defaultSegments => const [
    TranscriptSegment(
      start: Duration.zero,
      end: Duration(seconds: 2),
      text: 'Esta é uma nota de voz de exemplo gerada pelo fake.',
      words: [
        Word(
          text: 'Esta',
          start: Duration.zero,
          end: Duration(milliseconds: 400),
          probability: 0.98,
        ),
        Word(
          text: 'Taís',
          start: Duration(milliseconds: 400),
          end: Duration(milliseconds: 800),
          probability: 0.42,
        ),
      ],
    ),
    TranscriptSegment(
      start: Duration(seconds: 2),
      end: Duration(seconds: 4),
      text: 'O conteúdo real virá do whisper.cpp pelo plugin nativo.',
    ),
  ];

  final Map<RbPermission, PermissionStatus> _permissions;
  bool modelDownloaded;
  final bool systemAudioAvailable;
  final Duration levelsInterval;
  final List<TranscriptSegment> _transcriptResult;

  final _dictation = StreamController<DictationEvent>.broadcast();
  final _diagnostics = StreamController<NativeDiagnostic>.broadcast();
  final _live = <String, StreamController<LiveTranscript>>{};
  final Set<String> _recording = {};
  final Map<String, String> _dirs = {};
  final Set<WhisperModel> _downloadedModels = {...WhisperModel.values};

  // Hooks de teste.
  final List<String> pastedTexts = [];
  final List<DictationSound> playedSounds = [];
  final List<String> cancelledWavs = [];
  TranscriptionPriority? lastTranscribePriority;
  String? lastInitialPrompt;
  String? lastInputDeviceId;
  bool lastLiveTranscription = false;
  Hotkey? registeredHotkey;
  DictationMode? registeredMode;

  @override
  Future<PermissionStatus> permissionStatus(RbPermission p) async =>
      _permissions[p] ?? PermissionStatus.notDetermined;

  @override
  Future<PermissionStatus> requestPermission(RbPermission p) async {
    _permissions[p] = PermissionStatus.granted;
    return PermissionStatus.granted;
  }

  @override
  Future<RecordingHandle> startRecording({
    required String id,
    required String directory,
    required bool captureSystemAudio,
    bool liveTranscription = false,
    String? inputDeviceId,
  }) async {
    if (_recording.contains(id)) {
      throw const RbNativeException(
        RbNativeErrorCode.alreadyRecording,
        'Já existe uma gravação com este id.',
      );
    }
    _recording.add(id);
    _dirs[id] = directory;
    lastLiveTranscription = liveTranscription;
    lastInputDeviceId = inputDeviceId;
    await Directory(directory).create(recursive: true);
    await _touch(p.join(directory, '$id.mic.wav'));
    if (captureSystemAudio && systemAudioAvailable) {
      await _touch(p.join(directory, '$id.system.wav'));
    }
    await _touch(p.join(directory, '$id.m4a'));
    if (liveTranscription) {
      _live[id] = StreamController<LiveTranscript>.broadcast();
    }
    return RecordingHandle(id: id, startedAt: DateTime.now());
  }

  @override
  Future<RecordingResult> stopRecording(String id) async {
    if (!_recording.remove(id)) {
      throw const RbNativeException(
        RbNativeErrorCode.notRecording,
        'Nenhuma gravação ativa com este id.',
      );
    }
    final live = _live.remove(id);
    if (live != null && !live.isClosed) {
      live.add(LiveTranscript(recordingId: id, text: '', isFinal: true));
      await live.close();
    }
    final dir = _dirFor(id);
    final system = p.join(dir, '$id.system.wav');
    return RecordingResult(
      id: id,
      duration: const Duration(seconds: 4),
      micWavPath: p.join(dir, '$id.mic.wav'),
      systemWavPath: File(system).existsSync() ? system : null,
      playbackPath: p.join(dir, '$id.m4a'),
    );
  }

  @override
  Future<void> pauseRecording(String id) async => _assertRecording(id);

  @override
  Future<void> resumeRecording(String id) async => _assertRecording(id);

  @override
  Stream<AudioLevels> audioLevels(String id) {
    var t = 0;
    return Stream.periodic(levelsInterval, (_) {
      t++;
      final mic = (0.3 + 0.3 * ((t % 5) / 5)).clamp(0.0, 1.0);
      return AudioLevels(
        mic: mic,
        system: systemAudioAvailable ? (mic * 0.6) : null,
      );
    }).takeWhile((_) => _recording.contains(id));
  }

  @override
  Stream<LiveTranscript> liveTranscript(String id) =>
      _live.putIfAbsent(id, StreamController<LiveTranscript>.broadcast).stream;

  /// Emite um trecho de transcrição ao vivo (uso em dev/testes).
  void emitLiveTranscript(String id, String text, {bool isFinal = false}) {
    final ctrl = _live[id];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(LiveTranscript(recordingId: id, text: text, isFinal: isFinal));
    }
  }

  @override
  Future<List<AudioInputDevice>> inputDevices() async => const [
    AudioInputDevice(
      id: 'builtin',
      name: 'Microfone do MacBook Pro',
      isDefault: true,
    ),
    AudioInputDevice(id: 'airpods', name: 'AirPods Pro', isDefault: false),
    AudioInputDevice(id: 'shure', name: 'Shure MV7', isDefault: false),
  ];

  @override
  Future<List<double>> waveformPeaks(String path, int buckets) async {
    // Picos determinísticos do caminho (espelha `seedBars` do design).
    var x = 0;
    for (final c in path.codeUnits) {
      x = (x * 31 + c) % 9973;
    }
    final out = <double>[];
    for (var i = 0; i < buckets; i++) {
      x = (x * 16807 + 7) % 2147483647;
      final r = (x % 1000) / 1000.0;
      final env = 0.45 + 0.55 * math.sin(i / 7 + x % 3).abs();
      out.add((0.12 + r * 0.82 * env).clamp(0.0, 1.0));
    }
    return out;
  }

  @override
  Future<List<RecoverableRecording>> findRecoverableRecordings(
    String directory,
  ) async {
    final dir = Directory(directory);
    if (!dir.existsSync()) return [];
    final result = <RecoverableRecording>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.mic.wav')) continue;
      final id = name.substring(0, name.length - '.mic.wav'.length);
      if (_recording.contains(id)) continue;
      final system = p.join(directory, '$id.system.wav');
      result.add(
        RecoverableRecording(
          id: id,
          micWavPath: entity.path,
          systemWavPath: File(system).existsSync() ? system : null,
          duration: Duration.zero,
        ),
      );
    }
    return result;
  }

  @override
  Future<WhisperModelState> modelState(WhisperModel model) async {
    final has = modelDownloaded && _downloadedModels.contains(model);
    return WhisperModelState(
      downloaded: has,
      sizeBytes: has ? 1600000000 : null,
    );
  }

  @override
  Stream<double> downloadModel(WhisperModel model) async* {
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      yield i / 10;
    }
    _downloadedModels.add(model);
    modelDownloaded = true;
  }

  @override
  Future<void> deleteModel(WhisperModel model) async =>
      _downloadedModels.remove(model);

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    String? initialPrompt,
    TranscriptionPriority priority = TranscriptionPriority.normal,
    void Function(double progress)? onProgress,
  }) async {
    lastTranscribePriority = priority;
    lastInitialPrompt = initialPrompt;
    if (!modelDownloaded) {
      throw const RbNativeException(
        RbNativeErrorCode.modelMissing,
        'Modelo não baixado.',
      );
    }
    onProgress?.call(0.5);
    onProgress?.call(1);
    return _transcriptResult;
  }

  @override
  Future<void> cancelTranscription(String wavPath) async =>
      cancelledWavs.add(wavPath);

  @override
  Future<void> registerDictationHotkey(
    Hotkey hotkey,
    DictationMode mode,
  ) async {
    registeredHotkey = hotkey;
    registeredMode = mode;
  }

  @override
  Future<void> unregisterDictationHotkey() async {
    registeredHotkey = null;
    registeredMode = null;
  }

  @override
  Stream<DictationEvent> dictationEvents() => _dictation.stream;

  /// Emite um evento de ditado (uso em dev/testes).
  void emitDictation(DictationEvent event) => _dictation.add(event);

  @override
  Stream<NativeDiagnostic> diagnostics() => _diagnostics.stream;

  /// Emite um diagnóstico nativo (uso em dev/testes).
  void emitDiagnostic(NativeDiagnostic diagnostic) =>
      _diagnostics.add(diagnostic);

  @override
  Future<void> pasteText(String text) async => pastedTexts.add(text);

  @override
  Future<void> playDictationSound(DictationSound s) async =>
      playedSounds.add(s);

  Future<void> dispose() async {
    await _dictation.close();
    await _diagnostics.close();
    for (final c in _live.values) {
      if (!c.isClosed) await c.close();
    }
  }

  void _assertRecording(String id) {
    if (!_recording.contains(id)) {
      throw const RbNativeException(
        RbNativeErrorCode.notRecording,
        'Nenhuma gravação ativa com este id.',
      );
    }
  }

  String _dirFor(String id) => _dirs[id] ?? Directory.systemTemp.path;

  Future<void> _touch(String path) async {
    final file = File(path);
    if (!file.existsSync()) await file.writeAsBytes(const [0, 0, 0, 0]);
  }
}
