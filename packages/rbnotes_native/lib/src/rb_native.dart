import 'package:rbnotes_native/src/enums.dart';
import 'package:rbnotes_native/src/models.dart';

/// Public API of the `rbnotes_native` plugin.
///
/// The host app depends only on this interface (and the model/enum types),
/// never on the concrete channel implementation. Tests in the host app can
/// provide a fake that implements [RbNative]. Every native failure is raised
/// as a `RbNativeException` with one of the documented error codes.
abstract interface class RbNative {
  // ---------- Permissions ----------

  /// Current status of [p] without prompting the user.
  Future<PermissionStatus> permissionStatus(RbPermission p);

  /// Requests [p]: shows the system prompt (microphone) or opens the relevant
  /// Settings pane (screen recording / accessibility). Returns the status
  /// after the request resolves (for Settings-based permissions this reflects
  /// the state at call time, as the user grants asynchronously).
  Future<PermissionStatus> requestPermission(RbPermission p);

  // ---------- Recording ----------

  /// Starts a recording identified by [id], writing files under [directory].
  ///
  /// With [captureSystemAudio] true, writes `<id>.mic.wav` and
  /// `<id>.system.wav` (both 16 kHz mono PCM s16le). With false, only the mic
  /// file is written. A `<id>.m4a` stereo mix (L = mic, R = system) is written
  /// on [stopRecording] for playback.
  ///
  /// Throws `RbNativeException('already_recording')` if [id] is in progress.
  Future<RecordingHandle> startRecording({
    required String id,
    required String directory,
    required bool captureSystemAudio,
  });

  /// Stops the recording [id], finalizes the wav headers and the `.m4a` mix.
  ///
  /// Throws `RbNativeException('not_recording')` if [id] is unknown.
  Future<RecordingResult> stopRecording(String id);

  /// Pauses the recording [id] (audio is not written while paused).
  Future<void> pauseRecording(String id);

  /// Resumes a paused recording [id].
  Future<void> resumeRecording(String id);

  /// Audio levels (0..1) per channel, roughly 20 Hz, while [id] records.
  Stream<AudioLevels> audioLevels(String id);

  /// Orphaned `.wav` files (app crashed mid-recording) in [directory], with
  /// their headers repaired so they are playable/transcribable.
  Future<List<RecoverableRecording>> findRecoverableRecordings(
    String directory,
  );

  // ---------- Transcription (whisper.cpp + Metal) ----------

  /// Whether [model] is downloaded and its size on disk.
  Future<WhisperModelState> modelState(WhisperModel model);

  /// Downloads [model] into Application Support/RbNotes/models, emitting
  /// progress 0..1. The stream completes when the download finishes and emits
  /// a `RbNativeException('model_download_failed')` on error.
  Stream<double> downloadModel(WhisperModel model);

  /// Transcribes a 16 kHz mono wav at [wavPath] using [model]. Progress is
  /// reported through [onProgress] (0..1). Runs off the main thread.
  ///
  /// Throws `RbNativeException('model_missing')` if the model is not
  /// downloaded, `transcription_cancelled` if [cancelTranscription] was
  /// called, or `transcription_failed` on other errors.
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    void Function(double progress)? onProgress,
  });

  /// Cancels an in-flight [transcribe] for [wavPath].
  Future<void> cancelTranscription(String wavPath);

  // ---------- Global dictation ----------

  /// Registers the global dictation hotkey with the given [mode].
  ///
  /// Throws `RbNativeException('hotkey_conflict')` if the combination is
  /// already taken by the system or another app.
  Future<void> registerDictationHotkey(Hotkey hotkey, DictationMode mode);

  /// Unregisters the global dictation hotkey.
  Future<void> unregisterDictationHotkey();

  /// Stream of dictation events: started, stopped (with wav path), cancelled.
  Stream<DictationEvent> dictationEvents();

  /// Pastes [text] into the frontmost app: saves the pasteboard, writes the
  /// text, posts ⌘V and restores the original pasteboard after ~300 ms.
  /// Requires Accessibility permission.
  ///
  /// Throws `RbNativeException('paste_failed')` on failure.
  Future<void> pasteText(String text);

  /// Plays a system sound at the start or end of a dictation session.
  Future<void> playDictationSound(DictationSound s);
}
