# rbnotes_native

Native **macOS** plugin for **RbNotes** (Flutter desktop voice-notes app):

- **Permissions** — microphone, screen recording, accessibility.
- **Recording** — mic (`AVAudioEngine`) + system audio (`ScreenCaptureKit`),
  written incrementally as 16 kHz mono `s16le` wavs, plus a stereo `.m4a`
  (L = mic, R = system) for playback. Pause/resume, ~20 Hz RMS levels, and
  crash-recovery of orphaned wavs.
- **Transcription** — local [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
  with Metal, off the main thread, with progress + cancellation.
- **Global dictation** — Carbon hotkey (toggle) / `CGEventTap` (hold-to-talk),
  Esc to cancel, synthetic ⌘V paste with pasteboard restore, start/end sounds.

The public Dart API is defined in `docs/native-contract.md` and exported from
`package:rbnotes_native/rbnotes_native.dart` (`RbNative` + `MethodChannelRbNative`).

Minimum target: **macOS 13.0** (ScreenCaptureKit audio, whisper Metal framework).

---

## whisper.cpp integration

whisper.cpp is compiled **from source** into a self-contained
`macos/Frameworks/whisper.xcframework` by
[`scripts/build_whisper.sh`](scripts/build_whisper.sh):

- Pinned to tag **`v1.7.6`** (override with `WHISPER_REF`).
- Built `arm64` only by default (override with `WHISPER_ARCHS="arm64 x86_64"`).
- Metal shaders are **embedded** (`GGML_METAL_EMBED_LIBRARY=ON`), so there is
  no external `.metallib` at runtime — the framework is fully self-contained.
- CoreML is disabled; Metal + Accelerate only.

The framework is **not committed** to git (`.gitignore` excludes
`macos/Frameworks/` and `.whisper-build/`). It is (re)built automatically:

- the example `macos/Podfile` runs the script at evaluation time, before
  CocoaPods resolves `vendored_frameworks`;
- the podspec also declares a `before_compile` script phase as a fallback.

### Rebuild manually

```bash
# requires cmake + Xcode command line tools
brew install cmake
FORCE=1 packages/rbnotes_native/scripts/build_whisper.sh
```

The build is idempotent: it skips when `whisper.xcframework` already exists
(use `FORCE=1` to rebuild).

### Models

Models are downloaded on demand to
`~/Library/Application Support/RbNotes/models/` (atomic `.part` → rename, size
checked):

| `WhisperModel`     | file                             |
| ------------------ | -------------------------------- |
| `largeV3TurboQ5`   | `ggml-large-v3-turbo-q5_0.bin`   |
| `smallQ5`          | `ggml-small-q5_1.bin`            |

Source: `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/<file>`.

---

## Host app configuration

The app that embeds this plugin **must** configure the following (the bundled
`example/` already does — use it as a reference):

### Deployment target

`macos/Runner.xcodeproj` → `MACOSX_DEPLOYMENT_TARGET = 13.0` and
`platform :osx, '13.0'` in `macos/Podfile`.

### `Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Explain why RbNotes records the microphone.</string>
```

Screen recording and accessibility have **no** usage-description keys; macOS
shows its own prompts (`CGRequestScreenCaptureAccess`,
`AXIsProcessTrustedWithOptions`) and the user grants them in
**System Settings → Privacy & Security**.

### Entitlements (`DebugProfile.entitlements` and `Release.entitlements`)

```xml
<!-- App Sandbox MUST be OFF: CGEventTap, Accessibility and ScreenCaptureKit
     do not work under the sandbox. -->
<key>com.apple.security.app-sandbox</key><false/>
<key>com.apple.security.device.audio-input</key><true/>
<key>com.apple.security.network.client</key><true/> <!-- model downloads -->
```

### Hardened runtime

Enable the Hardened Runtime for distribution. Because the whisper framework is
loaded via `@rpath`, keep `com.apple.security.cs.disable-library-validation`
only if you run into validation issues with the vendored framework; otherwise
code-sign the embedded framework with your team identity (CocoaPods embeds and
signs it with the app).

### Permissions, step by step

The app is responsible for the UX of requesting permissions in order:

1. `microphone` — `requestPermission` shows the system prompt.
2. `screenRecording` — required only when `captureSystemAudio: true`; first
   request deep-links to Settings (user must re-launch after granting).
3. `accessibility` — required for global dictation (`CGEventTap`) and
   `pasteText`; `requestPermission` opens the Settings prompt.

---

## Logging

All native logging uses `os.Logger` with subsystem
`br.com.rodolfodebonis.rbnotes`. Stream it with:

```bash
log stream --predicate 'subsystem == "br.com.rodolfodebonis.rbnotes"' --level info
```

Categories: `permissions`, `recording`, `system-audio`, `whisper`,
`dictation`, `plugin`.

---

## Tests

```bash
cd packages/rbnotes_native
fvm flutter test          # Dart: channel serialization + error mapping
fvm flutter analyze       # very_good_analysis, clean
```

The channel plumbing (serialization, error-code mapping, event decoding) is
covered by Dart tests with a mocked `MethodChannel`/`EventChannel`. The native
audio/whisper/dictation paths require a real machine with granted permissions
and are verified manually via the example app.
