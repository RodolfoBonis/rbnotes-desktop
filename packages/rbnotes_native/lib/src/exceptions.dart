import 'package:flutter/foundation.dart';

/// Error codes used across the native boundary.
///
/// These mirror the codes documented in `docs/native-contract.md`. Every
/// failure that crosses the `MethodChannel` is normalized into a
/// [RbNativeException] carrying one of these codes so the host app never has
/// to deal with raw `PlatformException`s.
abstract final class RbNativeErrorCode {
  const RbNativeErrorCode._();

  static const String permissionDenied = 'permission_denied';
  static const String alreadyRecording = 'already_recording';
  static const String notRecording = 'not_recording';
  static const String systemAudioUnavailable = 'system_audio_unavailable';
  static const String modelMissing = 'model_missing';
  static const String modelDownloadFailed = 'model_download_failed';
  static const String transcriptionFailed = 'transcription_failed';
  static const String transcriptionCancelled = 'transcription_cancelled';
  static const String hotkeyConflict = 'hotkey_conflict';
  static const String pasteFailed = 'paste_failed';

  /// An enum/argument sent over the channel was missing or not recognized.
  static const String invalidArgument = 'invalid_argument';

  /// A dictation event map could not be decoded (unknown/missing `type`).
  static const String invalidEvent = 'invalid_event';

  /// The local diarization models are not downloaded (see
  /// `RbNative.diarize` / `downloadDiarizationModel`).
  static const String diarizationModelMissing = 'diarization_model_missing';

  /// Local diarization (sherpa-onnx) failed to run or produced no result.
  static const String diarizationFailed = 'diarization_failed';

  /// Registering/unregistering the macOS login item (`SMAppService`) failed.
  static const String loginItemFailed = 'login_item_failed';

  /// Fallback used when a platform error arrives without a recognized code
  /// (should not happen, but keeps the boundary total).
  static const String unknown = 'unknown';
}

/// The single exception type surfaced to the host app for every native
/// failure. [code] is one of [RbNativeErrorCode]; [message] is a
/// human-readable description.
@immutable
class RbNativeException implements Exception {
  const RbNativeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RbNativeException($code, $message)';

  @override
  bool operator ==(Object other) =>
      other is RbNativeException &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}
