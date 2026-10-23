## 0.0.1

- Initial release of the RbNotes native macOS plugin.
- Permissions: microphone, screen recording, accessibility.
- Recording: mic (AVAudioEngine) + system audio (ScreenCaptureKit), 16 kHz
  mono s16le wavs written incrementally, stereo `.m4a` playback mix,
  pause/resume, ~20 Hz RMS levels, crash recovery of orphaned wavs.
- Transcription: whisper.cpp with Metal (built from source into
  `whisper.xcframework`), background execution, progress + cancellation,
  on-demand model download.
- Global dictation: Carbon hotkey (toggle) / CGEventTap (hold-to-talk),
  Esc to cancel, synthetic ⌘V paste with pasteboard restore, sounds.
