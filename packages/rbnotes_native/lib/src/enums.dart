/// System permissions the plugin can query and request.
enum RbPermission { microphone, screenRecording, accessibility }

/// Result of a permission query/request.
enum PermissionStatus { granted, denied, notDetermined }

/// Whisper models supported by the plugin.
///
/// [largeV3TurboQ5] maps to `ggml-large-v3-turbo-q5_0.bin` and is the default;
/// [smallQ5] maps to `ggml-small-q5_1.bin` (faster, lower quality fallback).
enum WhisperModel { largeV3TurboQ5, smallQ5 }

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
    WhisperModel.largeV3TurboQ5 => 'largeV3TurboQ5',
    WhisperModel.smallQ5 => 'smallQ5',
  };

  /// The on-disk file name of the ggml model.
  String get fileName => switch (this) {
    WhisperModel.largeV3TurboQ5 => 'ggml-large-v3-turbo-q5_0.bin',
    WhisperModel.smallQ5 => 'ggml-small-q5_1.bin',
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
