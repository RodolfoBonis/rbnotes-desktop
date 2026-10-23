import FlutterMacOS
import Foundation

/// Error codes shared with the Dart side (see `docs/native-contract.md`).
/// Every failure that crosses the channel is one of these, wrapped in a
/// `FlutterError` whose `code` the Dart layer turns back into an
/// `RbNativeException`.
enum RbNativeError: Error {
  case permissionDenied(String)
  case alreadyRecording(String)
  case notRecording(String)
  case systemAudioUnavailable(String)
  case modelMissing(String)
  case modelDownloadFailed(String)
  case transcriptionFailed(String)
  case transcriptionCancelled(String)
  case hotkeyConflict(String)
  case pasteFailed(String)
  case invalidArgument(String)

  var code: String {
    switch self {
    case .permissionDenied: return "permission_denied"
    case .alreadyRecording: return "already_recording"
    case .notRecording: return "not_recording"
    case .systemAudioUnavailable: return "system_audio_unavailable"
    case .modelMissing: return "model_missing"
    case .modelDownloadFailed: return "model_download_failed"
    case .transcriptionFailed: return "transcription_failed"
    case .transcriptionCancelled: return "transcription_cancelled"
    case .hotkeyConflict: return "hotkey_conflict"
    case .pasteFailed: return "paste_failed"
    case .invalidArgument: return "invalid_argument"
    }
  }

  var message: String {
    switch self {
    case .permissionDenied(let m), .alreadyRecording(let m), .notRecording(let m),
      .systemAudioUnavailable(let m), .modelMissing(let m), .modelDownloadFailed(let m),
      .transcriptionFailed(let m), .transcriptionCancelled(let m), .hotkeyConflict(let m),
      .pasteFailed(let m), .invalidArgument(let m):
      return m
    }
  }

  var flutterError: FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}

extension FlutterError {
  /// Builds a `FlutterError` from any thrown error, preserving `RbNativeError`
  /// codes. Unknown errors use a neutral `unknown` code so the Dart side can
  /// still surface them as `RbNativeException`.
  static func from(_ error: Error) -> FlutterError {
    if let rb = error as? RbNativeError {
      return rb.flutterError
    }
    if let fe = error as? FlutterError {
      return fe
    }
    return FlutterError(
      code: "unknown",
      message: error.localizedDescription,
      details: nil
    )
  }
}
