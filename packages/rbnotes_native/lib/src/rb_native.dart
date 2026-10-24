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
  /// [inputDeviceId] selects the microphone (a device id from [inputDevices]);
  /// null uses the system default input.
  ///
  /// With [liveTranscription] true, the plugin transcribes the audio in ~5 s
  /// windows (with ~1 s overlap) using the [WhisperModel.tiny] model on a
  /// low-priority lane and emits incremental [LiveTranscript]s on
  /// [liveTranscript]. The tiny model is downloaded automatically if missing;
  /// live transcription never delays writing the wav files (windows are
  /// dropped if the transcription lane falls behind).
  ///
  /// Throws `RbNativeException('already_recording')` if [id] is in progress.
  Future<RecordingHandle> startRecording({
    required String id,
    required String directory,
    required bool captureSystemAudio,
    bool liveTranscription = false,
    String? inputDeviceId,
  });

  /// Stops the recording [id], finalizes the wav headers and the `.m4a` mix.
  ///
  /// Throws `RbNativeException('not_recording')` if [id] is unknown.
  Future<RecordingResult> stopRecording(String id);

  /// Pauses the recording [id] (audio is not written while paused, and live
  /// transcription is suspended).
  Future<void> pauseRecording(String id);

  /// Resumes a paused recording [id].
  Future<void> resumeRecording(String id);

  /// Audio levels (0..1) per channel, roughly 20 Hz, while [id] records.
  Stream<AudioLevels> audioLevels(String id);

  /// Incremental live-transcript updates for the recording [id] (only while it
  /// was started with `liveTranscription: true`). The accumulated,
  /// de-duplicated [LiveTranscript.text] grows over time; a final event with
  /// `isFinal == true` is emitted when the recording stops.
  Stream<LiveTranscript> liveTranscript(String id);

  /// Orphaned `.wav` files (app crashed mid-recording) in [directory], with
  /// their headers repaired so they are playable/transcribable.
  Future<List<RecoverableRecording>> findRecoverableRecordings(
    String directory,
  );

  /// Available audio input devices (for the "Microphone" picker). The default
  /// device has `isDefault == true`.
  Future<List<AudioInputDevice>> inputDevices();

  /// Peak amplitudes (0..1), one per bucket, of the audio file at [path]
  /// (`.wav` or `.m4a`), for drawing a waveform. Returns [buckets] values.
  Future<List<double>> waveformPeaks(String path, int buckets);

  /// Asynchronous, non-fatal native failures: write errors, audio device
  /// changes, system-audio drops, a disabled event tap or the dictation
  /// watchdog. A single permanent broadcast stream; the app can surface these
  /// to the user or to error monitoring.
  Stream<NativeDiagnostic> diagnostics();

  // ---------- Transcription (whisper.cpp + Metal) ----------

  /// Whether [model] is downloaded and its size on disk.
  Future<WhisperModelState> modelState(WhisperModel model);

  /// Downloads [model] into Application Support/RbNotes/models, emitting
  /// progress 0..1. The stream completes when the download finishes and emits
  /// a `RbNativeException('model_download_failed')` on error. Cancelling the
  /// stream subscription cancels the download.
  Stream<double> downloadModel(WhisperModel model);

  /// Deletes the on-disk file for [model]. No-op if it is not downloaded.
  Future<void> deleteModel(WhisperModel model);

  /// Transcribes a 16 kHz mono wav at [wavPath] using [model]. Progress is
  /// reported through [onProgress] (0..1). Runs off the main thread.
  ///
  /// [initialPrompt] seeds whisper's decoder with vocabulary/context (e.g. a
  /// glossary of names), mapped to `whisper_full_params.initial_prompt`.
  ///
  /// [priority] routes the job: [TranscriptionPriority.high] (dictation) runs
  /// on a separate native lane so it is not blocked by a long note.
  ///
  /// Each returned [TranscriptSegment] carries per-word timing/confidence in
  /// [TranscriptSegment.words].
  ///
  /// Throws `RbNativeException('model_missing')` if the model is not
  /// downloaded, `transcription_cancelled` if [cancelTranscription] was
  /// called, or `transcription_failed` on other errors.
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    String? initialPrompt,
    TranscriptionPriority priority = TranscriptionPriority.normal,
    void Function(double progress)? onProgress,
  });

  /// Cancels an in-flight [transcribe] for [wavPath].
  Future<void> cancelTranscription(String wavPath);

  // ---------- Global dictation ----------

  /// Registers the global dictation hotkey with the given [mode].
  ///
  /// Throws `RbNativeException('hotkey_conflict')` if the combination is
  /// already taken (toggle mode), or `permission_denied` if the event tap
  /// cannot be installed (hold-to-talk needs Accessibility).
  Future<void> registerDictationHotkey(Hotkey hotkey, DictationMode mode);

  /// Unregisters the global dictation hotkey.
  Future<void> unregisterDictationHotkey();

  /// Stream of dictation events: started, stopped (with wav path), cancelled.
  Stream<DictationEvent> dictationEvents();

  /// Pastes [text] into the frontmost app: saves the pasteboard, writes the
  /// text, posts ⌘V and restores the original pasteboard afterwards (only if
  /// it was not changed meanwhile). Requires Accessibility permission.
  ///
  /// Throws `RbNativeException('paste_failed')` on failure.
  Future<void> pasteText(String text);

  /// Plays a system sound at the start or end of a dictation session. The
  /// native side no longer plays these automatically; the app triggers them.
  Future<void> playDictationSound(DictationSound s);

  // ---------- Global hotkeys ----------

  /// Registers a global (system-wide) hotkey identified by [id], firing a
  /// toggle-style press on [globalHotkeyPressed] whenever [hotkey] is pressed
  /// in any app. Uses a Carbon `RegisterEventHotKey`, so — unlike dictation's
  /// hold-to-talk — it needs no Accessibility permission and does not consume
  /// other key events.
  ///
  /// Registering the same [id] again re-binds it to the new [hotkey].
  ///
  /// Throws `RbNativeException('hotkey_conflict')` if [hotkey] collides with
  /// the dictation hotkey or with a global hotkey already registered under a
  /// different [id], or if the system rejects the registration.
  Future<void> registerGlobalHotkey({
    required String id,
    required Hotkey hotkey,
  });

  /// Unregisters the global hotkey previously registered under [id]. No-op if
  /// [id] is not registered.
  Future<void> unregisterGlobalHotkey(String id);

  /// Emits the id of a registered global hotkey each time it is pressed. A
  /// single permanent broadcast stream, like [diagnostics]; the app filters by
  /// the id it cares about.
  Stream<String> globalHotkeyPressed();

  // ---------- Activity overlay (notch HUD) ----------

  /// Shows the Dynamic-Island-style activity overlay that emerges from the
  /// notch (or drops from the top of the menu bar on Macs without a notch).
  ///
  /// [mode] selects the recording HUD or the smaller dictation pill;
  /// [startedAt] seeds the elapsed-time counter (the native side advances it
  /// locally, so the timer keeps ticking without per-second updates).
  ///
  /// The overlay never steals focus from the frontmost app (so dictation can
  /// still paste into it) and floats above full-screen apps on every Space.
  /// Calling it again while visible re-targets the existing panel to [mode].
  Future<void> showActivityOverlay({
    required OverlayMode mode,
    required DateTime startedAt,
  });

  /// Pushes a partial update into the visible overlay. Every argument is
  /// optional; only the provided fields change.
  ///
  /// [micLevel]/[systemLevel] (0..1) drive the live waveform and may be sent at
  /// ~20 Hz — the native side coalesces them on the main thread. [liveText] is
  /// the accumulated live transcript (the last 1-2 lines are shown, new words
  /// fade in). [phase] switches between live/processing/done/error; [progress]
  /// (0..1) feeds the processing bar; [message] is the short title (done) or
  /// error text; [paused] toggles the paused styling of the REC dot.
  ///
  /// No-op if no overlay is currently shown.
  Future<void> updateActivityOverlay({
    double? micLevel,
    double? systemLevel,
    String? liveText,
    OverlayPhase? phase,
    double? progress,
    String? message,
    bool? paused,
  });

  /// Hides and tears down the overlay after [delay] (immediately by default).
  /// A non-zero [delay] lets the "done"/"pasted" state linger before it
  /// animates back into the notch. A new [showActivityOverlay] cancels a
  /// pending hide.
  Future<void> hideActivityOverlay({Duration delay = Duration.zero});

  /// User actions performed on the overlay (button taps or a click on the
  /// pill body). A single permanent broadcast stream, like [diagnostics].
  Stream<OverlayAction> overlayActions();
}
