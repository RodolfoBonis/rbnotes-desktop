# Fase 3 — contratos entre frentes

As três frentes (API, plugin e app) trabalham em paralelo contra estes contratos. Qualquer mudança é registrada aqui, com o motivo.

## API (`rbnotes-api`)

### Consumo de IA
`GET /v1/ai/usage?from=YYYY-MM-DD&to=YYYY-MM-DD&tz=America/Sao_Paulo`
- `from` e `to` são inclusivos. O padrão são os últimos 30 dias; o intervalo máximo é de 366 dias.

```json
{ "from":"2026-10-01","to":"2026-10-24","tz":"America/Sao_Paulo","currency":"USD","costIsEstimate":true,
  "quota":{"limit":200,"used24h":7},
  "totals":{"requests":42,"done":40,"errors":2,"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,"cacheReadTokens":0,"costUsd":1.234567,"durationMs":0},
  "byKind":[{"kind":"note_enrich","requests":30,"costUsd":0.9}],
  "days":[{"date":"2026-10-24","requests":5,"costUsd":0.12,"kinds":[{"kind":"note_enrich","requests":4,"costUsd":0.1,"inputTokens":0,"outputTokens":0}]}] }
```

### Exclusão de áudio
`DELETE /v1/notes/{id}/audio` → 204. É idempotente: se o objeto ou o upload não existirem, também responde 204. Aborta o multipart em andamento, se houver.

### Notas bloqueadas (cifradas)
- **No sync:** `data` de `note`, `segment_set`, `note_ai` ou `chat_message` pode chegar como `{"enc":"v1","nonce":"<b64>","ct":"<b64>"}`. Nesse caso o servidor:
  - guarda o valor como está;
  - não indexa no FTS e remove o que já estava indexado da nota;
  - exclui a nota de `ask`, `diary_month` e `weekly_summary`;
  - aceita o `note_ai` cifrado sem exigir título nem TL;DR.
- **Nos endpoints de IA:** `POST /ai/notes/{id}/enrich` e `/chat` aceitam `"ephemeral": true`. O worker roda normalmente, mas **não** grava a entidade `note_ai`/`chat_message` em texto claro; o resultado volta só pelo SSE (`done`). O `ai_jobs.result` dessas notas é limpo (fica `{}`) assim que o job termina.

### Resumo semanal
`POST /v1/ai/weekly-summary` com `{ "weekStart":"2026-10-19", "tz":"America/Sao_Paulo" }` → 202 + SSE. O `done` traz:

```json
{ "title":"…","summary":"…","highlights":["…"],"openTasks":[{"text":"…","noteId":"…"}],"themes":[{"name":"…","count":2}] }
```

As notas cifradas ficam de fora. O kind no banco é `weekly_summary`.

## Plugin (`rbnotes_native`), adições ao `RbNative`

```dart
// Trava do app (tela bloqueada / sono / proteção de tela)
Stream<LockTrigger> lockTriggers();            // screenLocked | systemSleep | screensaver
// Login item
Future<bool> launchAtLogin();                   // estado atual (SMAppService.mainApp)
Future<void> setLaunchAtLogin(bool enabled);
// Gravação: novas opções no startRecording
//   startRecording(..., bool noiseReduction = false, String? language)   // voice processing no input node
// Transcrição: idioma
//   transcribe(..., String language = 'auto')   // 'auto' | 'pt' | 'en' | 'es' ...
// Silêncios
Future<List<SilenceRange>> detectSilences(String wavPath, {Duration minSilence = const Duration(seconds: 2)}); // {startMs,endMs}
// Detecção de reunião
Stream<MeetingSignal> meetingSignals();         // {app: 'zoom.us'|'Microsoft Teams'|'Google Chrome'|..., micInUse: bool, startedAt}
Future<void> setMeetingDetection(bool enabled);
// Diarização local (sherpa-onnx)
Future<DiarizationModelState> diarizationModelState();
Stream<double> downloadDiarizationModel();
Future<List<SpeakerTurn>> diarize(String wavPath, {int? numSpeakers}); // {startMs,endMs,speaker:int}
// Overlay com o acento do app
//   showActivityOverlay(..., int? accentArgb)
// Exportação de áudio
//   já existe: playback .m4a
```

Os códigos de erro novos são `diarization_model_missing`, `diarization_failed` e `login_item_failed`.

### Nativo implementado (2026-10-24) — wire final

Tudo acima foi implementado no plugin. Detalhes de wire para o fake do app:

- **EventChannels novos (únicos e permanentes):** `rbnotes_native/lock_triggers`
  (`String`: `screenLocked`/`systemSleep`/`screensaver`),
  `rbnotes_native/meeting_signals` (`{app, micInUse, startedAtMs}`),
  `rbnotes_native/diarization_download` (`double` 0..1; `onListen` inicia o
  download, `onCancel` cancela).
- **Métodos:** `launchAtLogin` → `bool`; `setLaunchAtLogin {enabled}`;
  `detectSilences {wavPath, minSilenceMs}` → `[{startMs, endMs}]`;
  `setMeetingDetection {enabled}`; `diarizationModelState` → `{downloaded,
  sizeBytes?}`; `diarize {wavPath, numSpeakers}` → `[{startMs, endMs, speaker}]`.
- **`startRecording`** passa a enviar **sempre** `noiseReduction` (bool) e
  `language` (`String?`) além dos campos já existentes.
- **`transcribe`** aceita `language` incluindo `'auto'`. **Atenção:** o default
  do `transcribe` continua `'pt'` (não `'auto'`) por compatibilidade — passe o
  idioma explicitamente (`'auto'`/`'pt'`/`'en'`/`'es'`). O `language` do
  `startRecording` controla a transcrição **ao vivo**.
- **`showActivityOverlay`** passa a enviar `accentArgb` (`int?`, 0xAARRGGBB;
  null = acento padrão `#E0512E`).
- **Diagnóstico novo** em `diagnostics()`: `noise_reduction_unavailable` (o voice
  processing não pôde ligar; a gravação segue sem ruído reduzido).
- **Modelos de diarização** (download automático, SHA-256 + tamanho fixos):
  pyannote-segmentation-3-0 (5.992.913 B) + 3dspeaker CAM++ zh-cn 16k
  (28.281.138 B), em `~/Library/Application Support/RbNotes/models/diarization/`.
- **sherpa-onnx**: integrado via `scripts/build_sherpa.sh` (release oficial
  v2.0.0 pinado por SHA-256, sem binários no git). O `macos/Podfile` da raiz
  ganhou a linha de hook correspondente.
