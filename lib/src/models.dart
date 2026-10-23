import 'package:flutter/foundation.dart';
import 'package:rbnotes_native/src/enums.dart';

/// A global dictation hotkey: a virtual key code plus a set of modifiers.
@immutable
class Hotkey {
  const Hotkey({required this.keyCode, required this.modifiers});

  final int keyCode;
  final Set<HotkeyModifier> modifiers;

  Map<String, Object?> toMap() => <String, Object?>{
    'keyCode': keyCode,
    'modifiers': modifiers.map((m) => m.wireName).toList(),
  };

  @override
  bool operator ==(Object other) =>
      other is Hotkey &&
      other.keyCode == keyCode &&
      setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(keyCode, Object.hashAllUnordered(modifiers));
}

/// Handle returned when a recording starts.
@immutable
class RecordingHandle {
  const RecordingHandle({required this.id, required this.startedAt});

  factory RecordingHandle.fromMap(Map<Object?, Object?> map) => RecordingHandle(
    id: map['id']! as String,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['startedAtMs']! as num).toInt(),
    ),
  );

  final String id;
  final DateTime startedAt;
}

/// Result of a finished recording.
@immutable
class RecordingResult {
  const RecordingResult({
    required this.id,
    required this.duration,
    required this.micWavPath,
    required this.systemWavPath,
    required this.playbackPath,
  });

  factory RecordingResult.fromMap(Map<Object?, Object?> map) => RecordingResult(
    id: map['id']! as String,
    duration: Duration(milliseconds: (map['durationMs']! as num).toInt()),
    micWavPath: map['micWavPath']! as String,
    systemWavPath: map['systemWavPath'] as String?,
    playbackPath: map['playbackPath']! as String,
  );

  final String id;
  final Duration duration;
  final String micWavPath;

  /// Null when system audio capture was unavailable or disabled.
  final String? systemWavPath;

  /// `.m4a` stereo mix (L = mic, R = system) for playback.
  final String playbackPath;
}

/// Per-channel audio levels (0..1), streamed ~20 Hz while recording.
@immutable
class AudioLevels {
  const AudioLevels({required this.mic, required this.system});

  factory AudioLevels.fromMap(Map<Object?, Object?> map) => AudioLevels(
    mic: (map['mic']! as num).toDouble(),
    system: (map['system'] as num?)?.toDouble(),
  );

  final double mic;
  final double? system;
}

/// A `.wav` recording left behind by a crash, discovered during recovery.
@immutable
class RecoverableRecording {
  const RecoverableRecording({
    required this.id,
    required this.micWavPath,
    required this.systemWavPath,
    required this.duration,
  });

  factory RecoverableRecording.fromMap(Map<Object?, Object?> map) =>
      RecoverableRecording(
        id: map['id']! as String,
        micWavPath: map['micWavPath']! as String,
        systemWavPath: map['systemWavPath'] as String?,
        duration: Duration(milliseconds: (map['durationMs']! as num).toInt()),
      );

  final String id;
  final String micWavPath;
  final String? systemWavPath;
  final Duration duration;
}

/// Download/availability state of a Whisper model.
@immutable
class WhisperModelState {
  const WhisperModelState({required this.downloaded, required this.sizeBytes});

  factory WhisperModelState.fromMap(Map<Object?, Object?> map) =>
      WhisperModelState(
        downloaded: map['downloaded']! as bool,
        sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      );

  final bool downloaded;
  final int? sizeBytes;
}

/// A transcribed segment with start/end timestamps.
@immutable
class TranscriptSegment {
  const TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  factory TranscriptSegment.fromMap(Map<Object?, Object?> map) =>
      TranscriptSegment(
        start: Duration(milliseconds: (map['startMs']! as num).toInt()),
        end: Duration(milliseconds: (map['endMs']! as num).toInt()),
        text: map['text']! as String,
      );

  final Duration start;
  final Duration end;
  final String text;
}

/// Events emitted by the global dictation hotkey.
sealed class DictationEvent {
  const DictationEvent();

  /// Decodes an event map coming from the native side.
  factory DictationEvent.fromMap(Map<Object?, Object?> map) {
    final type = map['type']! as String;
    return switch (type) {
      'started' => const DictationStarted(),
      'stopped' => DictationStopped(map['wavPath']! as String),
      'cancelled' => const DictationCancelled(),
      _ => throw ArgumentError('Unknown DictationEvent: $type'),
    };
  }
}

/// Dictation recording has begun (mic → temporary wav).
final class DictationStarted extends DictationEvent {
  const DictationStarted();
}

/// Dictation finished; [wavPath] points at the recorded 16 kHz mono wav.
final class DictationStopped extends DictationEvent {
  const DictationStopped(this.wavPath);
  final String wavPath;
}

/// Dictation was cancelled (Esc) and the temporary wav discarded.
final class DictationCancelled extends DictationEvent {
  const DictationCancelled();
}
