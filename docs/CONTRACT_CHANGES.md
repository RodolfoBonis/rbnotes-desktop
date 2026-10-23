# Mudanças no contrato nativo

Registro de alterações em `docs/native-contract.md` (o quê e por quê). O outro
engenheiro lê este arquivo.

## 2026-10-23 — Implementação inicial do `rbnotes_native`

**Nenhuma mudança na API pública do contrato.** A interface `RbNative`, os
modelos, enums, códigos de erro e nomes de canais foram implementados
exatamente como especificado em `docs/native-contract.md`.

Detalhes de implementação (não afetam o contrato, mas úteis para o app):

- **Serialização (method channel).** Os mapas trafegam com chaves explícitas:
  - `startRecording` → `{id, directory, captureSystemAudio}`; retorna
    `{id, startedAtMs}`.
  - `stopRecording`/`RecordingResult` → `{id, durationMs, micWavPath,
    systemWavPath?, playbackPath}`.
  - `AudioLevels` → `{mic, system?}`; `RecoverableRecording` →
    `{id, micWavPath, systemWavPath?, durationMs}`.
  - `WhisperModelState` → `{downloaded, sizeBytes?}`; `TranscriptSegment` →
    `{startMs, endMs, text}`.
  - `DictationEvent` → `{type: 'started'|'stopped'|'cancelled', wavPath?}`.
  - Enums trafegam pelos nomes do contrato (`microphone`, `largeV3TurboQ5`,
    `holdToTalk`, etc.).
- **EventChannels e argumentos.** Os streams usam o argumento de
  `receiveBroadcastStream` como chave: `audioLevels` passa o `id`,
  `downloadModel` passa o nome do modelo, `transcription_progress` passa o
  `wavPath`, `dictation` não passa argumento. Assume-se **um stream ativo por
  canal por vez** (um gravação, uma transcrição, um download simultâneos) —
  suficiente para o app pessoal.
- **`transcribe`/`onProgress`.** O progresso chega pelo EventChannel
  `rbnotes_native/transcription_progress` correlacionado por `wavPath`; o
  `Future` resolve com os segmentos ao final. Cancelamento via
  `cancelTranscription(wavPath)` lança `transcription_cancelled`.
- **`m4a` mic-only.** Quando não há áudio de sistema, o `.m4a` recebe o mic
  nos dois canais (em vez de silêncio no canal direito) para um playback
  centralizado. `systemWavPath` continua `null`, conforme o contrato.
- **Hotkey + modificador `function`.** `RegisterEventHotKey` (Carbon, usado no
  modo `toggle`) não suporta o modificador `function`; ele é ignorado no
  registro Carbon. No `holdToTalk` (CGEventTap) o `function` é suportado
  (`maskSecondaryFn`). Sem impacto no contrato.

Se alguma mudança de API for necessária no futuro, ela será registrada aqui
com a data, o que mudou e o porquê.
