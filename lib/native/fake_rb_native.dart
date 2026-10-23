import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:rbnotes/native/rb_native.dart';

/// Implementação em memória do contrato nativo para desenvolvimento e testes.
///
/// Gera arquivos-placeholder reais em disco (para o player e a recuperação
/// funcionarem) e segmentos de transcrição canônicos. Todo comportamento é
/// configurável para os testes não dependerem de temporizadores reais.
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
       _transcriptResult =
           transcriptResult ??
           const [
             TranscriptSegment(
               start: Duration.zero,
               end: Duration(seconds: 2),
               text: 'Esta é uma nota de voz de exemplo gerada pelo fake.',
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
  final Set<String> _recording = {};
  final Map<String, String> _dirs = {};

  // Hooks de teste.
  final List<String> pastedTexts = [];
  final List<DictationSound> playedSounds = [];
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
  }) async {
    if (_recording.contains(id)) {
      throw const RbNativeException(
        RbNativeErrorCode.alreadyRecording,
        'Já existe uma gravação com este id.',
      );
    }
    _recording.add(id);
    _dirs[id] = directory;
    await Directory(directory).create(recursive: true);
    await _touch(p.join(directory, '$id.mic.wav'));
    if (captureSystemAudio && systemAudioAvailable) {
      await _touch(p.join(directory, '$id.system.wav'));
    }
    await _touch(p.join(directory, '$id.m4a'));
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
  Future<WhisperModelState> modelState(WhisperModel model) async =>
      WhisperModelState(
        downloaded: modelDownloaded,
        sizeBytes: modelDownloaded ? 1600000000 : null,
      );

  @override
  Stream<double> downloadModel(WhisperModel model) async* {
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      yield i / 10;
    }
    modelDownloaded = true;
  }

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    void Function(double progress)? onProgress,
  }) async {
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
  Future<void> cancelTranscription(String wavPath) async {}

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
  Future<void> pasteText(String text) async => pastedTexts.add(text);

  @override
  Future<void> playDictationSound(DictationSound s) async =>
      playedSounds.add(s);

  Future<void> dispose() => _dictation.close();

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
