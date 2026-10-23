import Foundation

/// An asynchronous, non-fatal native failure surfaced to Dart through the
/// `rbnotes_native/diagnostics` EventChannel. These do not interrupt a
/// recording/dictation by themselves; the app decides how to react.
struct NativeDiagnostic {
  let code: String
  let message: String
  let recordingId: String?

  init(_ code: String, _ message: String, recordingId: String? = nil) {
    self.code = code
    self.message = message
    self.recordingId = recordingId
  }

  var map: [String: Any] {
    var dict: [String: Any] = ["code": code, "message": message]
    if let recordingId { dict["recordingId"] = recordingId }
    return dict
  }
}

/// Diagnostic codes emitted on `rbnotes_native/diagnostics`. Documented in
/// `docs/native-contract.md`.
enum DiagnosticCode {
  static let audioConfigChanged = "audio_config_changed"
  static let audioEngineRestartFailed = "audio_engine_restart_failed"
  static let systemAudioStopped = "system_audio_stopped"
  static let writeFailed = "write_failed"
  static let tapDisabled = "tap_disabled"
  static let dictationWatchdog = "dictation_watchdog"
  static let dictationKeyStuck = "dictation_key_stuck"
}
