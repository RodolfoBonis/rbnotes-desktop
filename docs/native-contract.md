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
  /// No stop, mic e sistema são alinhados por host time (silêncio no início da fonte que começou depois).
  ///
  /// [inputDeviceId]: id de um dispositivo de [inputDevices] (null = default do sistema).
  /// [liveTranscription]: transcreve em janelas de ~5 s (sobreposição ~1 s) com o
  /// modelo `tiny` (baixado automaticamente se faltar) numa lane de baixa prioridade
  /// e emite [LiveTranscript] em [liveTranscript]. Nunca atrasa a escrita dos wavs.
  Future<RecordingHandle> startRecording({
    required String id,
    required String directory,
    required bool captureSystemAudio,
    bool liveTranscription = false,
    String? inputDeviceId,
  });
  Future<RecordingResult> stopRecording(String id);
  Future<void> pauseRecording(String id); // também suspende a transcrição ao vivo
  Future<void> resumeRecording(String id);
  /// Níveis de áudio (0..1) ~20 Hz, por canal, enquanto grava.
  Stream<AudioLevels> audioLevels(String id);
  /// Transcrição ao vivo acumulada (só se liveTranscription=true). O texto cresce
  /// ao longo do tempo (sobreposição já de-duplicada); um evento final com
  /// isFinal=true é emitido no stop.
  Stream<LiveTranscript> liveTranscript(String id);
  /// Arquivos .wav órfãos (app fechou durante gravação) para recuperação.
  Future<List<RecoverableRecording>> findRecoverableRecordings(String directory);
  /// Dispositivos de entrada disponíveis (picker "Microfone"). O default tem isDefault=true.
  Future<List<AudioInputDevice>> inputDevices();
  /// Picos (0..1), um por bucket, do áudio em [path] (.wav/.m4a), para desenhar waveform.
  Future<List<double>> waveformPeaks(String path, int buckets);
  /// Falhas assíncronas não-fatais. Stream único e permanente (broadcast).
  Stream<NativeDiagnostic> diagnostics();

  // ---------- Transcrição (whisper.cpp + Metal) ----------
  Future<WhisperModelState> modelState(WhisperModel model);
  /// Baixa o modelo para Application Support/RbNotes/models; emite progresso 0..1.
  /// Cancelar a assinatura do stream cancela o download. Verifica SHA-256 e tamanho.
  Stream<double> downloadModel(WhisperModel model);
  /// Remove o arquivo do modelo em disco (no-op se não baixado).
  Future<void> deleteModel(WhisperModel model);
  /// Transcreve um .wav 16 kHz mono. Progresso via [onProgress] (0..1).
  /// [initialPrompt] alimenta o vocabulário/contexto do decoder
  /// (`whisper_full_params.initial_prompt`).
  /// [priority] roteia o job: high (ditado) roda numa lane separada e não espera
  /// por uma nota longa (normal). Áudio em silêncio (RMS muito baixo) → lista vazia.
  /// Cada [TranscriptSegment] traz confiança por palavra em [TranscriptSegment.words].
  Future<List<TranscriptSegment>> transcribe({
    required String wavPath,
    required WhisperModel model,
    String language = 'pt',
    String? initialPrompt,
    TranscriptionPriority priority = TranscriptionPriority.normal,
    void Function(double progress)? onProgress,
  });
  Future<void> cancelTranscription(String wavPath);

  // ---------- Ditado global ----------
  /// Registra o atalho. mode=toggle (aperta inicia, aperta para) ou holdToTalk (segura).
  /// toggle usa Carbon hotkey (+ tap opcional só p/ Esc); holdToTalk usa um CGEventTap
  /// que CONSOME a tecla do atalho (⌥Space não digita no app em foco).
  Future<void> registerDictationHotkey(Hotkey hotkey, DictationMode mode);
  Future<void> unregisterDictationHotkey();
  /// Eventos do atalho: started (começou a gravar mic em wav temporário), stopped(wavPath), cancelled (Esc).
  Stream<DictationEvent> dictationEvents();
  /// Cola [text] no app em foco: cria os CGEvents, salva o pasteboard, escreve o texto
  /// (marcado transient/concealed), espera a liberação dos modificadores, posta ⌘V
  /// (keycode do "V" no layout atual, fallback 9) via CGEventPost e restaura o pasteboard
  /// original após ~500 ms — só se o changeCount não mudou. Requer Accessibility.
  Future<void> pasteText(String text);
  /// Toca o som de início/fim do ditado. O nativo NÃO toca sons automaticamente;
  /// é o app que chama este método.
  Future<void> playDictationSound(DictationSound s); // start | end

  // ---------- Atalhos globais ----------
  /// Registra um atalho global (toggle) identificado por [id]. Usa Carbon
  /// `RegisterEventHotKey` (sem Accessibility; a tecla é consumida pelo sistema).
  /// Registrar o mesmo [id] de novo re-vincula o atalho. Conflito com o atalho
  /// do ditado ou com um atalho já registrado em outro [id] → `hotkey_conflict`.
  Future<void> registerGlobalHotkey({required String id, required Hotkey hotkey});
  Future<void> unregisterGlobalHotkey(String id); // no-op se [id] não existe
  /// Emite o [id] a cada pressionar. Stream único e permanente (broadcast),
  /// como diagnostics(); o app filtra pelo id que interessa.
  Stream<String> globalHotkeyPressed();

  // ---------- Overlay de atividade (HUD do notch) ----------
  /// Mostra a pílula que sai do notch (ou desce do menu bar sem notch). Não rouba
  /// o foco do app em uso (o ditado continua colando no app em foco), flutua
  /// acima de apps em tela cheia e aparece em qualquer Space. Chamar de novo
  /// re-aponta o painel existente para [mode]. mode: recording | dictation.
  Future<void> showActivityOverlay({required OverlayMode mode, required DateTime startedAt});
  /// Atualização parcial do overlay visível (todos os campos opcionais; só os
  /// informados mudam). [micLevel]/[systemLevel] (0..1) podem vir a ~20 Hz (o
  /// nativo faz coalescing no main). phase: live | processing | done | error;
  /// message = título curto (done) / erro (error). No-op se nada estiver visível.
  Future<void> updateActivityOverlay({double? micLevel, double? systemLevel, String? liveText, OverlayPhase? phase, double? progress, String? message, bool? paused});
  /// Esconde e desmonta o overlay após [delay] (imediato por padrão). Um novo
  /// showActivityOverlay cancela um hide pendente.
  Future<void> hideActivityOverlay({Duration delay = Duration.zero});
  /// Ações do usuário no overlay (botões ou clique no corpo). Stream único e
  /// permanente (broadcast), como diagnostics().
  Stream<OverlayAction> overlayActions();
}

enum RbPermission { microphone, screenRecording, accessibility }
enum PermissionStatus { granted, denied, notDetermined }
// Ordem fastest→best. Default p/ notas: largeV3TurboQ5. tiny = transcrição ao vivo.
enum WhisperModel { tiny, smallQ5, medium, largeV3TurboQ5, largeV3 }
enum DictationMode { toggle, holdToTalk }
enum DictationSound { start, end }
enum TranscriptionPriority { normal, high } // default: normal
enum OverlayMode { recording, dictation }
enum OverlayPhase { live, processing, done, error }
enum OverlayAction { pause, resume, stop, discard, openApp }

class Hotkey { final int keyCode; final Set<HotkeyModifier> modifiers; }
enum HotkeyModifier { command, option, control, shift, function }

class RecordingHandle { final String id; final DateTime startedAt; }
class RecordingResult {
  final String id; final Duration duration;
  final String micWavPath; final String? systemWavPath; final String playbackPath; // .m4a
}
class AudioLevels { final double mic; final double? system; }
class AudioInputDevice { final String id; final String name; final bool isDefault; }
class LiveTranscript { final String recordingId; final String text; final bool isFinal; }
class RecoverableRecording { final String id; final String micWavPath; final String? systemWavPath; final Duration duration; }
class WhisperModelState { final bool downloaded; final int? sizeBytes; } // downloaded só se o tamanho bate
class Word { final String text; final Duration start; final Duration end; final double probability; } // probability 0..1
class TranscriptSegment {
  final Duration start; final Duration end; final String text;
  final List<Word>? words; // null quando o nativo não computou timestamps por palavra
}
class NativeDiagnostic { final String code; final String message; final String? recordingId; }
sealed class DictationEvent {}  // DictationStarted, DictationStopped(String wavPath), DictationCancelled

class RbNativeException implements Exception { final String code; final String message; }
```

## Modelos Whisper (arquivos ggml de `huggingface.co/ggerganov/whisper.cpp`)

| enum | wire | arquivo | tamanho (bytes) |
|---|---|---|---|
| `tiny` | `tiny` | `ggml-tiny.bin` | 77.691.713 |
| `smallQ5` | `smallQ5` | `ggml-small-q5_1.bin` | 190.085.487 |
| `medium` | `medium` | `ggml-medium-q5_0.bin` | 539.212.467 |
| `largeV3TurboQ5` | `largeV3TurboQ5` | `ggml-large-v3-turbo-q5_0.bin` | 574.041.195 |
| `largeV3` | `largeV3` | `ggml-large-v3-q5_0.bin` | 1.081.140.203 |

SHA-256 e tamanho de cada modelo são fixados no nativo (via `curl -sIL` → `x-linked-etag`/`x-linked-size`) e verificados no download; `modelState.downloaded` só é `true` quando o tamanho em disco bate exatamente.

## Códigos de erro
`permission_denied`, `already_recording`, `not_recording`, `system_audio_unavailable` (SCStream falhou; a gravação segue só com o mic e o resultado vem com `systemWavPath == null`), `model_missing`, `model_download_failed` (inclui falha ao deletar), `transcription_failed` (inclui falha ao ler áudio em `waveformPeaks`), `transcription_cancelled`, `hotkey_conflict`, `paste_failed`, `invalid_argument` (enum desconhecido / argumento ausente no wire / arquivo de áudio inexistente), `invalid_event` (o Dart não conseguiu decodificar um `DictationEvent`).

## Códigos de diagnóstico (`diagnostics()`)
Não são erros fatais; não interrompem a gravação/ditado por si só. O app decide como reagir (ex.: avisar o usuário, logar no monitoramento):

`audio_config_changed` (também emitido quando o dispositivo de entrada escolhido não pôde ser selecionado e caiu no default), `audio_engine_restart_failed`, `system_audio_stopped`, `write_failed`, `tap_disabled`, `dictation_watchdog`, `dictation_key_stuck`.

## Regras
- Canais via `MethodChannel('rbnotes_native')` + `EventChannel`s nomeados: `rbnotes_native/levels`, `rbnotes_native/dictation`, `rbnotes_native/diagnostics`, `rbnotes_native/model_download`, `rbnotes_native/transcription_progress`, `rbnotes_native/live_transcript`, `rbnotes_native/overlay_actions`,
  `rbnotes_native/global_hotkeys`.
- `transcription_progress` é um **stream único e permanente** que emite `{wavPath, progress}`; o Dart filtra por `wavPath` dentro de `transcribe`.
- `live_transcript` é um **stream único e permanente** que emite `{recordingId, text, isFinal}`; o Dart filtra por `recordingId` dentro de `liveTranscript`.
- `diagnostics` é um **stream único e permanente** que emite `NativeDiagnostic`.
- `TranscriptSegment.words`: o wire traz `words` como lista opcional de `{text, startMs, endMs, probability}`; ausente quando não houver timestamps por palavra. `transcribe` sempre computa; a transcrição ao vivo (tiny) **não** preenche `words`.
- Falante: o app junta os segmentos de `mic.wav` → "Eu" e de `system.wav` → "Outros", ordenados por `start`.
- Sem chave de API; tudo local. A transcrição ao vivo usa o modelo `tiny` e idioma `pt`.
- **Overlay de atividade.** `overlay_actions` é um stream **único e permanente**
  que emite uma `String` com o nome da ação (`pause`/`resume`/`stop`/`discard`/
  `openApp`); uma ação desconhecida vira `RbNativeException('invalid_event')` no
  Dart. O wire dos métodos: `showActivityOverlay {mode, startedAtMs}`,
  `updateActivityOverlay {micLevel?, systemLevel?, liveText?, phase?, progress?,
  message?, paused?}` (campos ausentes = sem mudança), `hideActivityOverlay
  {delayMs}`. O nativo mantém o cronômetro localmente a partir de `startedAtMs`
  (não precisa de update por segundo) e faz coalescing dos níveis no main (aceita
  ~20 Hz sem travar). O overlay usa a tela do menu bar (`NSScreen.screens.first`,
  fallback `.main`). Em Macs com notch (`safeAreaInsets.top` + `auxiliaryTopLeft/
  RightArea`) a pílula nasce das dimensões do notch e expande; sem notch, desce do
  menu bar. Respeita "Reduzir movimento" (fade em vez de spring). O painel é um
  `NSPanel` não-ativador (não rouba foco; o ditado cola no app em foco) acima de
  apps em tela cheia, em qualquer Space.
- **Atalhos globais.** `global_hotkeys` é um stream **único e permanente** que
  emite uma `String` com o `id` do atalho pressionado. Cada `id` vira um
  `EventHotKeyID` Carbon distinto (assinatura `RBGH`); o handler roteia por id e
  deixa passar (`eventNotHandledErr`) o que não for seu, então convive com o
  atalho do ditado (assinatura `RBNT`, que agora também checa o próprio id).
  Conflito = mesmo keyCode + mesmos modificadores Carbon
  (command/option/control/shift; `function` é ignorado) do atalho do ditado ou
  de outro `id` já registrado → `hotkey_conflict`. Wire:
  `registerGlobalHotkey {id, hotkey}`, `unregisterGlobalHotkey {id}`. Tudo é
  desregistrado no `deinit` do plugin.
