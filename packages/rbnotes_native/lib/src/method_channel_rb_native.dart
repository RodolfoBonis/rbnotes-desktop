import 'dart:async';

import 'package:flutter/services.dart';
import 'package:rbnotes_native/src/enums.dart';
import 'package:rbnotes_native/src/exceptions.dart';
import 'package:rbnotes_native/src/models.dart';
import 'package:rbnotes_native/src/rb_native.dart';

/// Channel names shared with the native side. Kept in one place so the Dart
/// and Swift sides are easy to keep in sync.
abstract final class RbNativeChannels {
  static const String method = 'rbnotes_native';
  static const String levels = 'rbnotes_native/levels';
  static const String dictation = 'rbnotes_native/dictation';
  static const String diagnostics = 'rbnotes_native/diagnostics';
  static const String modelDownload = 'rbnotes_native/model_download';
  static const String transcriptionProgress =
      'rbnotes_native/transcription_progress';
  static const String liveTranscript = 'rbnotes_native/live_transcript';
  static const String overlayActions = 'rbnotes_native/overlay_actions';
  static const String globalHotkeys = 'rbnotes_native/global_hotkeys';
  static const String lockTriggers = 'rbnotes_native/lock_triggers';
  static const String meetingSignals = 'rbnotes_native/meeting_signals';
  static const String diarizationDownload =
      'rbnotes_native/diarization_download';
}

/// `MethodChannel` backed implementation of [RbNative].
///
/// Normalizes every [PlatformException] / [MissingPluginException] into a
/// [RbNativeException] so no raw platform error leaks to the host app.
class MethodChannelRbNative implements RbNative {
  MethodChannelRbNative({
    MethodChannel? methodChannel,
    EventChannel? levelsChannel,
    EventChannel? dictationChannel,
    EventChannel? diagnosticsChannel,
    EventChannel? modelDownloadChannel,
    EventChannel? transcriptionProgressChannel,
    EventChannel? liveTranscriptChannel,
    EventChannel? overlayActionsChannel,
    EventChannel? globalHotkeysChannel,
    EventChannel? lockTriggersChannel,
    EventChannel? meetingSignalsChannel,
    EventChannel? diarizationDownloadChannel,
  }) : _method = methodChannel ?? const MethodChannel(RbNativeChannels.method),
       _levels = levelsChannel ?? const EventChannel(RbNativeChannels.levels),
       _dictation =
           dictationChannel ?? const EventChannel(RbNativeChannels.dictation),
       _diagnostics =
           diagnosticsChannel ??
           const EventChannel(RbNativeChannels.diagnostics),
       _modelDownload =
           modelDownloadChannel ??
           const EventChannel(RbNativeChannels.modelDownload),
       _transcriptionProgress =
           transcriptionProgressChannel ??
           const EventChannel(RbNativeChannels.transcriptionProgress),
       _liveTranscript =
           liveTranscriptChannel ??
           const EventChannel(RbNativeChannels.liveTranscript),
       _overlayActions =
           overlayActionsChannel ??
           const EventChannel(RbNativeChannels.overlayActions),
       _globalHotkeys =
           globalHotkeysChannel ??
           const EventChannel(RbNativeChannels.globalHotkeys),
       _lockTriggers =
           lockTriggersChannel ??
           const EventChannel(RbNativeChannels.lockTriggers),
       _meetingSignals =
           meetingSignalsChannel ??
           const EventChannel(RbNativeChannels.meetingSignals),
       _diarizationDownload =
           diarizationDownloadChannel ??
           const EventChannel(RbNativeChannels.diarizationDownload);

  final MethodChannel _method;
  final EventChannel _levels;
  final EventChannel _dictation;
  final EventChannel _diagnostics;
  final EventChannel _modelDownload;
  final EventChannel _transcriptionProgress;
  final EventChannel _liveTranscript;
  final EventChannel _overlayActions;
  final EventChannel _globalHotkeys;
  final EventChannel _lockTriggers;
  final EventChannel _meetingSignals;
  final EventChannel _diarizationDownload;

  /// Single permanent fan-out of the native transcription-progress stream.
  /// Each native event is a `{wavPath, progress}` map; [transcribe] subscribes
  /// to this broadcast and filters by its own `wavPath`. The underlying
  /// EventChannel is listened to exactly once (no listen/cancel per call).
  StreamController<Map<Object?, Object?>>? _progressController;
  StreamSubscription<Object?>? _progressChannelSub;

  /// Single permanent fan-out of the native live-transcript stream. Each native
  /// event is a `{recordingId, text, isFinal}` map; [liveTranscript] subscribes
  /// to this broadcast and filters by recording id.
  StreamController<Map<Object?, Object?>>? _liveController;
  StreamSubscription<Object?>? _liveChannelSub;

  Stream<Map<Object?, Object?>> get _progressEvents {
    final existing = _progressController;
    if (existing != null) return existing.stream;

    final controller = StreamController<Map<Object?, Object?>>.broadcast();
    _progressController = controller;
    _progressChannelSub =
        _mapStreamErrors(
          _transcriptionProgress.receiveBroadcastStream(),
        ).listen(
          (event) {
            if (event is Map<Object?, Object?>) controller.add(event);
          },
          onError: controller.addError,
        );
    return controller.stream;
  }

  Stream<Map<Object?, Object?>> get _liveEvents {
    final existing = _liveController;
    if (existing != null) return existing.stream;

    final controller = StreamController<Map<Object?, Object?>>.broadcast();
    _liveController = controller;
    _liveChannelSub = _mapStreamErrors(_liveTranscript.receiveBroadcastStream())
        .listen(
          (event) {
            if (event is Map<Object?, Object?>) controller.add(event);
          },
          onError: controller.addError,
        );
    return controller.stream;
  }

  /// Releases the permanent fan-out subscriptions. Optional; the plugin
  /// normally lives for the app's lifetime.
  Future<void> dispose() async {
    await _progressChannelSub?.cancel();
    await _progressController?.close();
    _progressChannelSub = null;
    _progressController = null;
    await _liveChannelSub?.cancel();
    await _liveController?.close();
    _liveChannelSub = null;
    _liveController = null;
  }

  // ---------- Permissions ----------

  @override
  Future<PermissionStatus> permissionStatus(RbPermission p) async {
    final value = await _invoke<String>('permissionStatus', {
      'permission': p.wireName,
    });
    return PermissionStatusWire.fromWire(value);
  }

  @override
  Future<PermissionStatus> requestPermission(RbPermission p) async {
    final value = await _invoke<String>('requestPermission', {
      'permission': p.wireName,
    });
    return PermissionStatusWire.fromWire(value);
  }

  // ---------- Recording ----------

  @override
  Future<RecordingHandle> startRecording({
    required String id,
    required String directory,
    required bool captureSystemAudio,
    bool liveTranscription = false,
    String? inputDeviceId,
    bool noiseReduction = false,
    String? language,
  }) async {
    final map = await _invoke<Map<Object?, Object?>>('startRecording', {
      'id': id,
      'directory': directory,
      'captureSystemAudio': captureSystemAudio,
      'liveTranscription': liveTranscription,
      'inputDeviceId': inputDeviceId,
      'noiseReduction': noiseReduction,
      'language': language,
    });
    return RecordingHandle.fromMap(map);
  }

  @override
  Future<RecordingResult> stopRecording(String id) async {
    final map = await _invoke<Map<Object?, Object?>>('stopRecording', {
      'id': id,
    });
    return RecordingResult.fromMap(map);
  }

  @override
  Future<void> pauseRecording(String id) =>
      _invoke<void>('pauseRecording', {'id': id});

  @override
  Future<void> resumeRecording(String id) =>
      _invoke<void>('resumeRecording', {'id': id});

  @override
  Stream<AudioLevels> audioLevels(String id) =>
      _mapStreamErrors(_levels.receiveBroadcastStream(id))
          .map((event) => AudioLevels.fromMap(event! as Map<Object?, Object?>));

  @override
  Stream<LiveTranscript> liveTranscript(String id) => _liveEvents
      .where((map) => map['recordingId'] == id)
      .map(LiveTranscript.fromMap);

  @override
  Future<List<RecoverableRecording>> findRecoverableRecordings(
    String directory,
  ) async {
    final list = await _invoke<List<Object?>>('findRecoverableRecordings', {
      'directory': directory,
    });
    return list
        .cast<Map<Object?, Object?>>()
        .map(RecoverableRecording.fromMap)
        .toList();
  }

  @override
  Future<List<AudioInputDevice>> inputDevices() async {
    final list = await _invoke<List<Object?>>('inputDevices');
    return list
        .cast<Map<Object?, Object?>>()
        .map(AudioInputDevice.fromMap)
        .toList();
  }

  @override
  Future<List<double>> waveformPeaks(String path, int buckets) async {
    final list = await _invoke<List<Object?>>('waveformPeaks', {
      'path': path,
      'buckets': buckets,
    });
    return list.map((e) => (e! as num).toDouble()).toList();
  }

  @override
  Stream<NativeDiagnostic> diagnostics() =>
      _mapStreamErrors(_diagnostics.receiveBroadcastStream()).map(
        (event) => NativeDiagnostic.fromMap(event! as Map<Object?, Object?>),
      );

  // ---------- Transcription ----------

  @override
  Future<WhisperModelState> modelState(WhisperModel model) async {
    final map = await _invoke<Map<Object?, Object?>>('modelState', {
      'model': model.wireName,
    });
    return WhisperModelState.fromMap(map);
  }

  @override
  Stream<double> downloadModel(WhisperModel model) =>
      _mapStreamErrors(_modelDownload.receiveBroadcastStream(model.wireName))
          .map((event) => (event! as num).toDouble());

  @override
  Future<void> deleteModel(WhisperModel model) =>
      _invoke<void>('deleteModel', {'model': model.wireName});

  @override
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    String? initialPrompt,
    TranscriptionPriority priority = TranscriptionPriority.normal,
    void Function(double progress)? onProgress,
  }) async {
    StreamSubscription<Map<Object?, Object?>>? progressSub;
    if (onProgress != null) {
      // Filter the shared, permanent progress stream by this wavPath.
      progressSub = _progressEvents.listen((map) {
        if (map['wavPath'] == wavPath) {
          final value = map['progress'];
          if (value is num) onProgress(value.toDouble());
        }
      });
    }
    try {
      final list = await _invoke<List<Object?>>('transcribe', {
        'wavPath': wavPath,
        'model': model.wireName,
        'language': language,
        'initialPrompt': initialPrompt,
        'priority': priority.wireName,
      });
      return list
          .cast<Map<Object?, Object?>>()
          .map(TranscriptSegment.fromMap)
          .toList();
    } finally {
      // A failure to cancel the (internal) subscription must never mask the
      // transcription result/error.
      try {
        await progressSub?.cancel();
      } on Object {
        // ignore: swallow — cancelling our own stream sub is best-effort.
      }
    }
  }

  @override
  Future<void> cancelTranscription(String wavPath) =>
      _invoke<void>('cancelTranscription', {'wavPath': wavPath});

  // ---------- Dictation ----------

  @override
  Future<void> registerDictationHotkey(Hotkey hotkey, DictationMode mode) =>
      _invoke<void>('registerDictationHotkey', {
        'hotkey': hotkey.toMap(),
        'mode': mode.wireName,
      });

  @override
  Future<void> unregisterDictationHotkey() =>
      _invoke<void>('unregisterDictationHotkey');

  @override
  Stream<DictationEvent> dictationEvents() => _mapStreamErrors(
    _dictation.receiveBroadcastStream(),
  ).map((event) => DictationEvent.fromMap(event! as Map<Object?, Object?>));

  @override
  Future<void> pasteText(String text) =>
      _invoke<void>('pasteText', {'text': text});

  @override
  Future<void> playDictationSound(DictationSound s) =>
      _invoke<void>('playDictationSound', {'sound': s.wireName});

  // ---------- Global hotkeys ----------

  @override
  Future<void> registerGlobalHotkey({
    required String id,
    required Hotkey hotkey,
  }) => _invoke<void>('registerGlobalHotkey', {
    'id': id,
    'hotkey': hotkey.toMap(),
  });

  @override
  Future<void> unregisterGlobalHotkey(String id) =>
      _invoke<void>('unregisterGlobalHotkey', {'id': id});

  @override
  Stream<String> globalHotkeyPressed() =>
      _mapStreamErrors(_globalHotkeys.receiveBroadcastStream())
          .map((event) => event! as String);

  // ---------- Activity overlay ----------

  @override
  Future<void> showActivityOverlay({
    required OverlayMode mode,
    required DateTime startedAt,
    int? accentArgb,
  }) => _invoke<void>('showActivityOverlay', {
    'mode': mode.wireName,
    'startedAtMs': startedAt.millisecondsSinceEpoch,
    'accentArgb': accentArgb,
  });

  @override
  Future<void> updateActivityOverlay({
    double? micLevel,
    double? systemLevel,
    String? liveText,
    OverlayPhase? phase,
    double? progress,
    String? message,
    bool? paused,
  }) => _invoke<void>('updateActivityOverlay', {
    'micLevel': micLevel,
    'systemLevel': systemLevel,
    'liveText': liveText,
    'phase': phase?.wireName,
    'progress': progress,
    'message': message,
    'paused': paused,
  });

  @override
  Future<void> hideActivityOverlay({Duration delay = Duration.zero}) =>
      _invoke<void>('hideActivityOverlay', {'delayMs': delay.inMilliseconds});

  @override
  Stream<OverlayAction> overlayActions() =>
      _mapStreamErrors(_overlayActions.receiveBroadcastStream()).map(
        (event) => OverlayActionWire.fromWire(event! as String),
      );

  // ---------- App lock triggers (Phase 3) ----------

  @override
  Stream<LockTrigger> lockTriggers() =>
      _mapStreamErrors(_lockTriggers.receiveBroadcastStream())
          .map((event) => LockTriggerWire.fromWire(event! as String));

  // ---------- Login item (Phase 3) ----------

  @override
  Future<bool> launchAtLogin() async {
    final value = await _invoke<bool>('launchAtLogin');
    return value;
  }

  @override
  Future<void> setLaunchAtLogin(bool enabled) =>
      _invoke<void>('setLaunchAtLogin', {'enabled': enabled});

  // ---------- Silence detection (Phase 3) ----------

  @override
  Future<List<SilenceRange>> detectSilences(
    String wavPath, {
    Duration minSilence = const Duration(seconds: 2),
  }) async {
    final list = await _invoke<List<Object?>>('detectSilences', {
      'wavPath': wavPath,
      'minSilenceMs': minSilence.inMilliseconds,
    });
    return list
        .cast<Map<Object?, Object?>>()
        .map(SilenceRange.fromMap)
        .toList();
  }

  // ---------- Meeting detection (Phase 3) ----------

  @override
  Stream<MeetingSignal> meetingSignals() =>
      _mapStreamErrors(_meetingSignals.receiveBroadcastStream()).map(
        (event) => MeetingSignal.fromMap(event! as Map<Object?, Object?>),
      );

  @override
  Future<void> setMeetingDetection(bool enabled) =>
      _invoke<void>('setMeetingDetection', {'enabled': enabled});

  // ---------- Local diarization (sherpa-onnx, Phase 3) ----------

  @override
  Future<DiarizationModelState> diarizationModelState() async {
    final map = await _invoke<Map<Object?, Object?>>('diarizationModelState');
    return DiarizationModelState.fromMap(map);
  }

  @override
  Stream<double> downloadDiarizationModel() =>
      _mapStreamErrors(_diarizationDownload.receiveBroadcastStream())
          .map((event) => (event! as num).toDouble());

  @override
  Future<List<SpeakerTurn>> diarize(String wavPath, {int? numSpeakers}) async {
    final list = await _invoke<List<Object?>>('diarize', {
      'wavPath': wavPath,
      'numSpeakers': numSpeakers,
    });
    return list.cast<Map<Object?, Object?>>().map(SpeakerTurn.fromMap).toList();
  }

  // ---------- Helpers ----------

  /// Invokes a method and normalizes platform errors into
  /// [RbNativeException]. [T] is the expected non-null return type (use
  /// `void` for methods with no return value).
  Future<T> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      if (T == _voidType) {
        await _method.invokeMethod<void>(method, args);
        return null as T;
      }
      final result = await _method.invokeMethod<T>(method, args);
      return result as T;
    } on PlatformException catch (e) {
      throw RbNativeException(e.code, e.message ?? '');
    } on MissingPluginException catch (e) {
      throw RbNativeException(
        RbNativeErrorCode.unknown,
        e.message ?? 'Missing plugin implementation for $method',
      );
    }
  }

  /// Converts [PlatformException]s flowing through an [EventChannel] stream
  /// into [RbNativeException]s.
  Stream<Object?> _mapStreamErrors(Stream<Object?> source) {
    return source.transform(
      StreamTransformer<Object?, Object?>.fromHandlers(
        handleError: (error, stackTrace, sink) {
          if (error is PlatformException) {
            sink.addError(
              RbNativeException(error.code, error.message ?? ''),
              stackTrace,
            );
          } else {
            sink.addError(error, stackTrace);
          }
        },
      ),
    );
  }

  static final Type _voidType = _typeOf<void>();
  static Type _typeOf<X>() => X;
}
