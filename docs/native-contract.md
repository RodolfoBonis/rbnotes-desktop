# Contrato Dart ↔ nativo (`packages/rbnotes_native`)

Plugin Flutter **macOS-only** em Swift. O app consome **apenas** esta API Dart pública (`package:rbnotes_native/rbnotes_native.dart`). O app testa contra um fake que implementa a mesma interface.

Todos os erros nativos chegam como `RbNativeException(code, message)`; os códigos estão listados abaixo. Nada de `PlatformException` vazando para o app.

```dart
abstract interface class RbNative {
  // ---------- Permissões ----------
  Future<PermissionStatus> permissionStatus(RbPermission p);
  /// Abre o prompt do sistema (mic) ou o painel de Ajustes (screen recording / accessibility).
  Future<PermissionStatus> requestPermission(RbPermission p);

  // ---------- Gravação ----------
  /// Inicia a gravação. Com [captureSystemAudio], grava 2 arquivos separados:
  /// `<dir>/<id>.mic.wav` e `<dir>/<id>.system.wav` (16 kHz, mono, PCM s16le).
  /// Com false, só o mic. Também grava `<dir>/<id>.m4a` (mix estéreo L=mic R=sistema) para playback.
  Future<RecordingHandle> startRecording({
    required String id,
    required String directory,
    required bool captureSystemAudio,
  });
  Future<RecordingResult> stopRecording(String id);
  Future<void> pauseRecording(String id);
  Future<void> resumeRecording(String id);
  /// Níveis de áudio (0..1) ~20 Hz, por canal, enquanto grava.
  Stream<AudioLevels> audioLevels(String id);
  /// Arquivos .wav órfãos (app fechou durante gravação) para recuperação.
  Future<List<RecoverableRecording>> findRecoverableRecordings(String directory);

  // ---------- Transcrição (whisper.cpp + Metal) ----------
  Future<WhisperModelState> modelState(WhisperModel model);
  /// Baixa o modelo para Application Support/RbNotes/models; emite progresso 0..1.
  Stream<double> downloadModel(WhisperModel model);
  /// Transcreve um .wav 16 kHz mono. Progresso via [onProgress] (0..1).
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    void Function(double progress)? onProgress,
  });
  Future<void> cancelTranscription(String wavPath);

  // ---------- Ditado global ----------
  /// Registra o atalho. mode=toggle (aperta inicia, aperta para) ou holdToTalk (segura).
  Future<void> registerDictationHotkey(Hotkey hotkey, DictationMode mode);
  Future<void> unregisterDictationHotkey();
  /// Eventos do atalho: started (começou a gravar mic em wav temporário), stopped(wavPath), cancelled (Esc).
  Stream<DictationEvent> dictationEvents();
  /// Cola [text] no app em foco: salva o pasteboard, escreve o texto, posta ⌘V (keycode 9 + Command) via CGEventPost
  /// e restaura o pasteboard original após ~300 ms. Requer Accessibility.
  Future<void> pasteText(String text);
  Future<void> playDictationSound(DictationSound s); // start | end
}

enum RbPermission { microphone, screenRecording, accessibility }
enum PermissionStatus { granted, denied, notDetermined }
enum WhisperModel { largeV3TurboQ5, smallQ5 } // default: largeV3TurboQ5 (ggml-large-v3-turbo-q5_0.bin)
enum DictationMode { toggle, holdToTalk }
enum DictationSound { start, end }

class Hotkey { final int keyCode; final Set<HotkeyModifier> modifiers; }
enum HotkeyModifier { command, option, control, shift, function }

class RecordingHandle { final String id; final DateTime startedAt; }
class RecordingResult {
  final String id; final Duration duration;
  final String micWavPath; final String? systemWavPath; final String playbackPath; // .m4a
}
class AudioLevels { final double mic; final double? system; }
class RecoverableRecording { final String id; final String micWavPath; final String? systemWavPath; final Duration duration; }
class WhisperModelState { final bool downloaded; final int? sizeBytes; }
class TranscriptSegment { final Duration start; final Duration end; final String text; }
sealed class DictationEvent {}  // DictationStarted, DictationStopped(String wavPath), DictationCancelled

class RbNativeException implements Exception { final String code; final String message; }
```

## Códigos de erro
`permission_denied`, `already_recording`, `not_recording`, `system_audio_unavailable` (SCStream falhou; a gravação segue só com o mic e o resultado vem com `systemWavPath == null`), `model_missing`, `model_download_failed`, `transcription_failed`, `transcription_cancelled`, `hotkey_conflict`, `paste_failed`.

## Regras
- Canais via `MethodChannel('rbnotes_native')` + `EventChannel`s nomeados (`rbnotes_native/levels`, `rbnotes_native/dictation`, `rbnotes_native/model_download`, `rbnotes_native/transcription_progress`).
- Falante: o app junta os segmentos de `mic.wav` → "Eu" e de `system.wav` → "Outros", ordenados por `start`.
- Sem chave de API; tudo local.
