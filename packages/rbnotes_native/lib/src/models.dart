import 'package:flutter/foundation.dart';
import 'package:rbnotes_native/src/enums.dart';
import 'package:rbnotes_native/src/exceptions.dart';

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

/// A single word with its timing and whisper confidence (0..1).
///
/// Produced from whisper token-level timestamps/probabilities by aggregating
/// the sub-word tokens of a segment back into words. [probability] is the mean
/// of the token probabilities that make up the word.
@immutable
class Word {
  const Word({
    required this.text,
    required this.start,
    required this.end,
    required this.probability,
  });

  factory Word.fromMap(Map<Object?, Object?> map) => Word(
    text: map['text']! as String,
    start: Duration(milliseconds: (map['startMs']! as num).toInt()),
    end: Duration(milliseconds: (map['endMs']! as num).toInt()),
    probability: (map['probability']! as num).toDouble(),
  );

  final String text;
  final Duration start;
  final Duration end;

  /// Whisper confidence for this word, 0..1 (mean of its token probabilities).
  final double probability;

  @override
  bool operator ==(Object other) =>
      other is Word &&
      other.text == text &&
      other.start == start &&
      other.end == end &&
      other.probability == probability;

  @override
  int get hashCode => Object.hash(text, start, end, probability);
}

/// A transcribed segment with start/end timestamps and, optionally, per-word
/// timing/confidence.
@immutable
class TranscriptSegment {
  const TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
    this.words,
  });

  factory TranscriptSegment.fromMap(Map<Object?, Object?> map) =>
      TranscriptSegment(
        start: Duration(milliseconds: (map['startMs']! as num).toInt()),
        end: Duration(milliseconds: (map['endMs']! as num).toInt()),
        text: map['text']! as String,
        words: (map['words'] as List<Object?>?)
            ?.cast<Map<Object?, Object?>>()
            .map(Word.fromMap)
            .toList(),
      );

  final Duration start;
  final Duration end;
  final String text;

  /// Per-word timing and confidence, or null when the native side did not
  /// compute word timestamps (the field is optional on the wire).
  final List<Word>? words;
}

/// An incremental, in-recording ("live") transcript update emitted while a
/// recording started with `liveTranscription: true` is running.
///
/// [text] is the accumulated, cleaned transcript so far (the overlap between
/// consecutive audio windows is de-duplicated on the native side, so the app
/// can render [text] directly). [isFinal] is true for the last update, emitted
/// when the recording stops.
@immutable
class LiveTranscript {
  const LiveTranscript({
    required this.recordingId,
    required this.text,
    required this.isFinal,
  });

  factory LiveTranscript.fromMap(Map<Object?, Object?> map) => LiveTranscript(
    recordingId: map['recordingId']! as String,
    text: map['text']! as String,
    isFinal: map['isFinal']! as bool,
  );

  final String recordingId;
  final String text;
  final bool isFinal;

  @override
  bool operator ==(Object other) =>
      other is LiveTranscript &&
      other.recordingId == recordingId &&
      other.text == text &&
      other.isFinal == isFinal;

  @override
  int get hashCode => Object.hash(recordingId, text, isFinal);
}

/// An available audio input device (the "Microphone" picker in the UI).
@immutable
class AudioInputDevice {
  const AudioInputDevice({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  factory AudioInputDevice.fromMap(Map<Object?, Object?> map) =>
      AudioInputDevice(
        id: map['id']! as String,
        name: map['name']! as String,
        isDefault: map['isDefault']! as bool,
      );

  /// Stable device identifier (CoreAudio device UID), passed back to
  /// `startRecording(inputDeviceId:)`.
  final String id;
  final String name;
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is AudioInputDevice &&
      other.id == id &&
      other.name == name &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(id, name, isDefault);
}

/// An asynchronous, non-fatal native failure (write error, device change,
/// system-audio drop, dictation watchdog, …) emitted on `RbNative.diagnostics`.
@immutable
class NativeDiagnostic {
  const NativeDiagnostic({
    required this.code,
    required this.message,
    this.recordingId,
  });

  factory NativeDiagnostic.fromMap(Map<Object?, Object?> map) =>
      NativeDiagnostic(
        code: map['code']! as String,
        message: map['message']! as String,
        recordingId: map['recordingId'] as String?,
      );

  /// A stable diagnostic code (see `docs/native-contract.md`).
  final String code;
  final String message;

  /// The recording the diagnostic relates to, when applicable.
  final String? recordingId;

  @override
  bool operator ==(Object other) =>
      other is NativeDiagnostic &&
      other.code == code &&
      other.message == message &&
      other.recordingId == recordingId;

  @override
  int get hashCode => Object.hash(code, message, recordingId);
}

/// A detected run of near-silence in a recording, from [start] to [end]
/// (Phase 3, "remove long silences").
@immutable
class SilenceRange {
  const SilenceRange({required this.start, required this.end});

  factory SilenceRange.fromMap(Map<Object?, Object?> map) => SilenceRange(
    start: Duration(milliseconds: (map['startMs']! as num).toInt()),
    end: Duration(milliseconds: (map['endMs']! as num).toInt()),
  );

  final Duration start;
  final Duration end;

  Duration get duration => end - start;

  @override
  bool operator ==(Object other) =>
      other is SilenceRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// A meeting-detection signal (Phase 3, "suggest recording a meeting").
///
/// Emitted at the start and the end of a detected meeting. [micInUse] is true
/// while the input device is in use by another process (meeting in progress)
/// and false on the end event. [app] is the correlated foreground/running app
/// (e.g. `zoom.us`, `Microsoft Teams`, `Google Chrome`) or empty if unknown.
/// [startedAt] is when the meeting started.
@immutable
class MeetingSignal {
  const MeetingSignal({
    required this.app,
    required this.micInUse,
    required this.startedAt,
  });

  factory MeetingSignal.fromMap(Map<Object?, Object?> map) => MeetingSignal(
    app: map['app']! as String,
    micInUse: map['micInUse']! as bool,
    startedAt: DateTime.fromMillisecondsSinceEpoch(
      (map['startedAtMs']! as num).toInt(),
    ),
  );

  final String app;
  final bool micInUse;
  final DateTime startedAt;

  @override
  bool operator ==(Object other) =>
      other is MeetingSignal &&
      other.app == app &&
      other.micInUse == micInUse &&
      other.startedAt == startedAt;

  @override
  int get hashCode => Object.hash(app, micInUse, startedAt);
}

/// Download/availability state of the local diarization models
/// (sherpa-onnx segmentation + speaker-embedding), Phase 3.
///
/// [downloaded] is true only when every required model file is present with
/// its exact expected size; [sizeBytes] is the total on-disk size then.
@immutable
class DiarizationModelState {
  const DiarizationModelState({
    required this.downloaded,
    required this.sizeBytes,
  });

  factory DiarizationModelState.fromMap(Map<Object?, Object?> map) =>
      DiarizationModelState(
        downloaded: map['downloaded']! as bool,
        sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      );

  final bool downloaded;
  final int? sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is DiarizationModelState &&
      other.downloaded == downloaded &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(downloaded, sizeBytes);
}

/// A diarized speaker turn (Phase 3): the span [start]..[end] was spoken by
/// [speaker] (a zero-based cluster index, rendered as "Pessoa 1/2…" by the app).
@immutable
class SpeakerTurn {
  const SpeakerTurn({
    required this.start,
    required this.end,
    required this.speaker,
  });

  factory SpeakerTurn.fromMap(Map<Object?, Object?> map) => SpeakerTurn(
    start: Duration(milliseconds: (map['startMs']! as num).toInt()),
    end: Duration(milliseconds: (map['endMs']! as num).toInt()),
    speaker: (map['speaker']! as num).toInt(),
  );

  final Duration start;
  final Duration end;
  final int speaker;

  @override
  bool operator ==(Object other) =>
      other is SpeakerTurn &&
      other.start == start &&
      other.end == end &&
      other.speaker == speaker;

  @override
  int get hashCode => Object.hash(start, end, speaker);
}

/// Events emitted by the global dictation hotkey.
sealed class DictationEvent {
  const DictationEvent();

  /// Decodes an event map coming from the native side.
  ///
  /// Throws `RbNativeException('invalid_event')` if the map is missing/has an
  /// unknown `type` (so a malformed event never silently becomes a default).
  factory DictationEvent.fromMap(Map<Object?, Object?> map) {
    final type = map['type'];
    switch (type) {
      case 'started':
        return const DictationStarted();
      case 'stopped':
        final wavPath = map['wavPath'];
        if (wavPath is! String) {
          throw const RbNativeException(
            RbNativeErrorCode.invalidEvent,
            'DictationStopped missing wavPath',
          );
        }
        return DictationStopped(wavPath);
      case 'cancelled':
        return const DictationCancelled();
      default:
        throw RbNativeException(
          RbNativeErrorCode.invalidEvent,
          'Unknown DictationEvent: $type',
        );
    }
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
