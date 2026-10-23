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
  `downloadModel` passa o nome do modelo, `dictation` não passa argumento.
- **`m4a` mic-only.** Quando não há áudio de sistema, o `.m4a` recebe o mic
  nos dois canais (em vez de silêncio no canal direito) para um playback
  centralizado. `systemWavPath` continua `null`, conforme o contrato.
- **Hotkey + modificador `function`.** `RegisterEventHotKey` (Carbon, usado no
  modo `toggle`) não suporta o modificador `function`; ele é ignorado no
  registro Carbon. No `holdToTalk` (CGEventTap) o `function` é suportado
  (`maskSecondaryFn`). Sem impacto no contrato.

## 2026-10-23 — Correções de code review (mudanças de contrato)

Estas **mudam a API pública** — o app precisa se adequar:

- **Novo stream `diagnostics()`** → `Stream<NativeDiagnostic>` no canal
  `rbnotes_native/diagnostics` (único e permanente). `NativeDiagnostic` =
  `{code, message, recordingId?}`. Emite falhas assíncronas **não-fatais**:
  erro de escrita (`write_failed`), troca de dispositivo de áudio
  (`audio_config_changed`), falha ao reiniciar o engine
  (`audio_engine_restart_failed`), queda do áudio de sistema
  (`system_audio_stopped`), event tap desativado (`tap_disabled`), e watchdog
  do ditado (`dictation_watchdog`). O app pode exibir ao usuário e/ou logar no
  monitoramento de erros. Não interrompem gravação/ditado por si sós.

- **`transcribe` ganhou `priority`** (`TranscriptionPriority { normal, high }`,
  default `normal`; wire `{priority: 'normal'|'high'}`). `high` (use no ditado)
  roda numa lane nativa separada, com contexto whisper próprio, então o ditado
  não espera por uma nota longa em transcrição.

- **`transcription_progress` agora é um stream único e permanente** que emite
  `{wavPath, progress}` (antes: um stream por `wavPath`). No Dart,
  `transcribe` apenas filtra o broadcast interno por `wavPath` — não há
  `listen`/`cancel` por chamada no EventChannel. Falha ao cancelar a
  assinatura interna nunca mascara o resultado da transcrição.

- **Novo código de erro `invalid_argument`** — enum desconhecido / argumento
  ausente no wire agora lança isso (antes: default silencioso ou código
  genérico). O Dart também pode lançar **`invalid_event`** se não conseguir
  decodificar um `DictationEvent` (`DictationEvent.fromMap`).

- **`registerDictationHotkey` pode lançar `permission_denied`** (além de
  `hotkey_conflict`): no `holdToTalk` o CGEventTap é obrigatório e, se não
  puder ser instalado (Accessibility), o registro falha com `permission_denied`
  (não `hotkey_conflict`). No `toggle`, o tap (só p/ Esc) é opcional e não
  falha o registro.

- **Sons do ditado:** o Swift **não toca mais sons automaticamente** no
  start/stop do ditado. O app deve chamar `playDictationSound(start|end)` nos
  momentos apropriados (o outro engenheiro mantém as chamadas no lado Dart).

Comportamento reforçado (sem mudar assinaturas):

- `pasteText` cria os CGEvents antes de tocar no pasteboard, marca o item como
  transient/concealed, espera a liberação dos modificadores do atalho (fonte
  `.privateState`), resolve o keycode do "V" pelo layout atual (fallback 9) e
  restaura o pasteboard após ~500 ms **só se** o `changeCount` não mudou.
- `downloadModel`: SHA-256 e tamanho fixos por modelo são verificados antes do
  rename; `onCancel` do stream cancela o `URLSessionDownloadTask`; downloads
  concorrentes do mesmo modelo são rejeitados com `model_download_failed`.
- `modelState.downloaded` é `true` só quando o tamanho em disco bate com o
  esperado.
- Gravação: mic e sistema são alinhados por host time no stop (pad de silêncio
  no início da fonte que começou depois); se o `.wav` de sistema ficar
  ilegível, o resultado degrada para mic-only (`systemWavPath == null`).
