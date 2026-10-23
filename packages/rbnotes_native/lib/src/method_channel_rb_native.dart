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
  static const String modelDownload = 'rbnotes_native/model_download';
  static const String transcriptionProgress =
      'rbnotes_native/transcription_progress';
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
    EventChannel? modelDownloadChannel,
    EventChannel? transcriptionProgressChannel,
  }) : _method = methodChannel ?? const MethodChannel(RbNativeChannels.method),
       _levels = levelsChannel ?? const EventChannel(RbNativeChannels.levels),
       _dictation =
           dictationChannel ?? const EventChannel(RbNativeChannels.dictation),
       _modelDownload =
           modelDownloadChannel ??
           const EventChannel(RbNativeChannels.modelDownload),
       _transcriptionProgress =
           transcriptionProgressChannel ??
           const EventChannel(RbNativeChannels.transcriptionProgress);

  final MethodChannel _method;
  final EventChannel _levels;
  final EventChannel _dictation;
  final EventChannel _modelDownload;
  final EventChannel _transcriptionProgress;

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
  }) async {
    final map = await _invoke<Map<Object?, Object?>>('startRecording', {
      'id': id,
      'directory': directory,
      'captureSystemAudio': captureSystemAudio,
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
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    void Function(double progress)? onProgress,
  }) async {
    StreamSubscription<Object?>? progressSub;
    if (onProgress != null) {
      // Correlated by wavPath; native emits raw doubles for this key.
      progressSub = _transcriptionProgress
          .receiveBroadcastStream(wavPath)
          .listen((event) => onProgress((event! as num).toDouble()));
    }
    try {
      final list = await _invoke<List<Object?>>('transcribe', {
        'wavPath': wavPath,
        'model': model.wireName,
        'language': language,
      });
      return list
          .cast<Map<Object?, Object?>>()
          .map(TranscriptSegment.fromMap)
          .toList();
    } finally {
      await progressSub?.cancel();
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
