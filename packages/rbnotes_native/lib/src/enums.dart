import 'package:rbnotes_native/src/exceptions.dart';

/// System permissions the plugin can query and request.
enum RbPermission { microphone, screenRecording, accessibility }

/// Result of a permission query/request.
enum PermissionStatus { granted, denied, notDetermined }

/// Whisper models supported by the plugin, ordered roughly from fastest/least
/// accurate to slowest/most accurate.
///
/// - [tiny] → `ggml-tiny.bin`: used for live (in-recording) transcription and
///   as a lightweight fallback.
/// - [smallQ5] → `ggml-small-q5_1.bin`.
/// - [medium] → `ggml-medium-q5_0.bin`.
/// - [largeV3TurboQ5] → `ggml-large-v3-turbo-q5_0.bin` (the default).
/// - [largeV3] → `ggml-large-v3-q5_0.bin` (highest quality, largest).
enum WhisperModel { tiny, smallQ5, medium, largeV3TurboQ5, largeV3 }

/// Dictation hotkey behaviour.
///
/// [toggle]: press once to start, press again to stop.
/// [holdToTalk]: records while the key is held, stops on key up.
enum DictationMode { toggle, holdToTalk }

/// System sounds played at the edges of a dictation session.
enum DictationSound { start, end }

/// Hotkey modifiers (map to Carbon modifier masks on the native side).
enum HotkeyModifier { command, option, control, shift, function }

/// Scheduling priority for `RbNative.transcribe`.
///
/// [high] (used for dictation) runs on a separate native lane so it never
/// waits behind a long [normal] note transcription. Defaults to [normal].
enum TranscriptionPriority { normal, high }

/// Wire names shared with the native side. Keeping the mapping explicit
/// (instead of relying on `Enum.name`) makes the protocol stable even if the
/// Dart enum members are ever reordered or renamed.
extension RbPermissionWire on RbPermission {
  String get wireName => switch (this) {
    RbPermission.microphone => 'microphone',
    RbPermission.screenRecording => 'screenRecording',
    RbPermission.accessibility => 'accessibility',
  };
}

extension PermissionStatusWire on PermissionStatus {
  static PermissionStatus fromWire(String value) => switch (value) {
    'granted' => PermissionStatus.granted,
    'denied' => PermissionStatus.denied,
    'notDetermined' => PermissionStatus.notDetermined,
    _ => throw ArgumentError('Unknown PermissionStatus: $value'),
  };
}

extension WhisperModelWire on WhisperModel {
  String get wireName => switch (this) {
    WhisperModel.tiny => 'tiny',
    WhisperModel.smallQ5 => 'smallQ5',
    WhisperModel.medium => 'medium',
    WhisperModel.largeV3TurboQ5 => 'largeV3TurboQ5',
    WhisperModel.largeV3 => 'largeV3',
  };

  /// The on-disk file name of the ggml model.
  String get fileName => switch (this) {
    WhisperModel.tiny => 'ggml-tiny.bin',
    WhisperModel.smallQ5 => 'ggml-small-q5_1.bin',
    WhisperModel.medium => 'ggml-medium-q5_0.bin',
    WhisperModel.largeV3TurboQ5 => 'ggml-large-v3-turbo-q5_0.bin',
    WhisperModel.largeV3 => 'ggml-large-v3-q5_0.bin',
  };
}

extension DictationModeWire on DictationMode {
  String get wireName => switch (this) {
    DictationMode.toggle => 'toggle',
    DictationMode.holdToTalk => 'holdToTalk',
  };
}

extension DictationSoundWire on DictationSound {
  String get wireName => switch (this) {
    DictationSound.start => 'start',
    DictationSound.end => 'end',
  };
}

extension HotkeyModifierWire on HotkeyModifier {
  String get wireName => switch (this) {
    HotkeyModifier.command => 'command',
    HotkeyModifier.option => 'option',
    HotkeyModifier.control => 'control',
    HotkeyModifier.shift => 'shift',
    HotkeyModifier.function => 'function',
  };
}

extension TranscriptionPriorityWire on TranscriptionPriority {
  String get wireName => switch (this) {
    TranscriptionPriority.normal => 'normal',
    TranscriptionPriority.high => 'high',
  };
}

/// Which activity the notch overlay represents.
///
/// [recording] shows the full recording HUD (REC dot, timer, live waveform,
/// live transcript and Pause/Finish/Discard controls). [dictation] shows the
/// smaller dictation pill (waveform + "Ditando…" + the paste hint).
enum OverlayMode { recording, dictation }

/// The visual phase of the activity overlay, driving which content it renders.
///
/// [live] is the active recording/dictation state; [processing] shows the
/// "Transcrevendo / Gerando resumo" progress; [done] shows a check and a short
/// title before auto-hiding; [error] shows an icon and a short message.
enum OverlayPhase { live, processing, done, error }

/// A user action performed on the activity overlay.
///
/// [openApp] is emitted when the user clicks the body of the pill (outside the
/// explicit buttons) to bring RbNotes to the front.
enum OverlayAction { pause, resume, stop, discard, openApp }

extension OverlayModeWire on OverlayMode {
  String get wireName => switch (this) {
    OverlayMode.recording => 'recording',
    OverlayMode.dictation => 'dictation',
  };
}

extension OverlayPhaseWire on OverlayPhase {
  String get wireName => switch (this) {
    OverlayPhase.live => 'live',
    OverlayPhase.processing => 'processing',
    OverlayPhase.done => 'done',
    OverlayPhase.error => 'error',
  };
}

extension OverlayActionWire on OverlayAction {
  /// Decodes an action coming from the native side.
  ///
  /// Throws `RbNativeException('invalid_event')` for an unknown value, so a
  /// malformed action never silently becomes a default.
  static OverlayAction fromWire(String value) => switch (value) {
    'pause' => OverlayAction.pause,
    'resume' => OverlayAction.resume,
    'stop' => OverlayAction.stop,
    'discard' => OverlayAction.discard,
    'openApp' => OverlayAction.openApp,
    _ => throw RbNativeException(
      RbNativeErrorCode.invalidEvent,
      'Unknown OverlayAction: $value',
    ),
  };
}
