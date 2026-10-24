# Mudanças no contrato nativo

Registro de alterações em `docs/native-contract.md` (o quê e por quê). O outro
engenheiro lê este arquivo.

## 2026-10-23 — Atalhos globais genéricos (`registerGlobalHotkey`)

Estas **mudam a API pública** (aditivas; nada existente foi renomeado). Motivação:
o atalho global "Gravar nota" — toca em qualquer app, modo toggle (⌥⇧Espaço por
padrão), inicia/para uma gravação com o overlay do notch. Generaliza o registro
de hotkeys que antes só existia para o ditado.

- **3 métodos novos na `RbNative`:**
  - `registerGlobalHotkey({required String id, required Hotkey hotkey})` — wire
    `registerGlobalHotkey {id, hotkey}`. Carbon `RegisterEventHotKey` (toggle),
    **sem Accessibility** e a tecla é consumida pelo sistema. Registrar o mesmo
    `id` de novo re-vincula.
  - `unregisterGlobalHotkey(String id)` — wire `unregisterGlobalHotkey {id}`.
    No-op se o `id` não existe.
  - `globalHotkeyPressed()` → `Stream<String>` no EventChannel **único e
    permanente** `rbnotes_native/global_hotkeys`. Emite o `id` do atalho
    pressionado; o app filtra pelo id que lhe interessa.

- **Novo EventChannel:** `rbnotes_native/global_hotkeys` (wire: `String` = id).

- **`hotkey_conflict` ganhou um novo uso:** além do ditado, `registerGlobalHotkey`
  lança `hotkey_conflict` quando o combo colide com o atalho do ditado ou com um
  atalho global já registrado em outro `id`. Conflito = mesmo keyCode + mesmos
  modificadores Carbon (command/option/control/shift; `function` é ignorado, pois
  o Carbon não o expressa).

Detalhes de implementação (não afetam assinaturas):

- Cada `id` mapeia um `EventHotKeyID` Carbon distinto (assinatura `RBGH`). O
  handler roteia por id e devolve `eventNotHandledErr` para o que não é seu, de
  modo que **convive** com o atalho de ditado em modo toggle.
- O handler do ditado (assinatura `RBNT`, id 1) passou a **checar o próprio
  `EventHotKeyID`** antes de disparar o toggle — antes assumia ser o único
  hotkey registrado; com os atalhos globais isso deixou de valer.
- A detecção de conflito é lógica pura (`HotkeyCombo` em `RbNativeCore`, testada
  em `HotkeyComboTests`).
- Tudo é desregistrado no `deinit` do plugin.

## 2026-10-23 — Overlay de atividade que sai do notch (HUD Dynamic Island)

Estas **mudam a API pública** (aditivas; nada existente foi renomeado). O app
consome esta API para mostrar o HUD de gravação/ditado por cima de qualquer app.

- **4 métodos novos na `RbNative`:**
  - `showActivityOverlay({required OverlayMode mode, required DateTime startedAt})`
    — wire `showActivityOverlay {mode, startedAtMs}`. Mostra a pílula emergindo do
    notch (ou descendo do menu bar sem notch). Chamar de novo re-aponta o painel
    existente. `mode`: `recording` (HUD completo) ou `dictation` (pílula menor).
  - `updateActivityOverlay({double? micLevel, double? systemLevel, String? liveText,
    OverlayPhase? phase, double? progress, String? message, bool? paused})` — wire
    `updateActivityOverlay {micLevel?, systemLevel?, liveText?, phase?, progress?,
    message?, paused?}`. **Todos opcionais**: só os campos enviados mudam. Pode ser
    chamado a ~20 Hz (níveis são coalescidos no main). No-op se nada está visível.
  - `hideActivityOverlay({Duration delay = Duration.zero})` — wire
    `hideActivityOverlay {delayMs}`. Esconde após o delay; um novo `show` cancela
    um hide pendente.
  - `overlayActions()` → `Stream<OverlayAction>` no EventChannel **único e
    permanente** `rbnotes_native/overlay_actions`. O wire é uma `String` com o nome
    da ação; o Dart decodifica para `OverlayAction`.

- **Enums novos:**
  - `OverlayMode { recording, dictation }` (wire: `recording`/`dictation`).
  - `OverlayPhase { live, processing, done, error }` (wire igual aos nomes).
  - `OverlayAction { pause, resume, stop, discard, openApp }` (wire igual).
    `openApp` = clique no corpo da pílula (fora dos botões).

- **Novo EventChannel:** `rbnotes_native/overlay_actions`.

- **Novo uso de `invalid_event`:** uma ação desconhecida no stream
  `overlay_actions` vira `RbNativeException('invalid_event')` (como no
  `DictationEvent`).

Comportamento (não afeta assinaturas, mas o app deve saber):

- **Fases & auto-hide.** `phase: done` auto-esconde após ~1,5 s (o app não
  precisa chamar `hide`). `error` **persiste** (o app decide quando esconder).
  `live`/`processing` ficam até o app mandar outra coisa. No `recording`, o HUD
  nasce **expandido** e colapsa para compacto após ~2 s (ou enquanto o mouse
  estiver sobre ele fica expandido). No `dictation`, `phase: done` mostra
  "Colado" e deve ser seguido de `hide`.
- **Cronômetro local.** O nativo avança o tempo a partir de `startedAtMs`; não é
  preciso enviar update por segundo. Pausar (`paused: true`) congela o tempo.
- **Foco & janelas.** `NSPanel` não-ativador (`.nonactivatingPanel`,
  `level = .statusBar`, `collectionBehavior [.canJoinAllSpaces,
  .fullScreenAuxiliary, .stationary]`, `hidesOnDeactivate = false`, sem sombra do
  sistema — a sombra é desenhada no SwiftUI). **Não rouba o foco** do app em uso,
  então o ditado cola no app em foco; aceita cliques nos botões sem ativar o
  RbNotes; funciona em qualquer Space e por cima de apps em tela cheia.
- **Tela & notch.** Usa a tela do menu bar (`NSScreen.screens.first`, fallback
  `.main`). Notch detectado por `safeAreaInsets.top` (≥20 pt) +
  `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` para a largura; a pílula nasce
  com as dimensões do notch e faz spring (~0,35 s) para o tamanho alvo. Sem notch,
  desce do menu bar (`NSStatusBar.system.thickness`). Respeita "Reduzir
  movimento" (`accessibilityDisplayShouldReduceMotion` → fade em vez de spring).
- **Níveis.** O app pode enviar `micLevel`/`systemLevel` via
  `updateActivityOverlay` (ex.: reencaminhando `audioLevels(id)`); o overlay
  mantém uma janela rolante das amostras para as barras. Alternativa documentada:
  o próprio app alimenta os níveis — o nativo não se inscreve sozinho na gravação.

Limitações conhecidas:

- O posicionamento exato "dentro do notch" depende do modelo (largura do notch
  varia); a geometria é derivada de `auxiliaryTop*Area`, testada em
  `RbNativeCore` (`NotchGeometryTests`) mas não há calibração por modelo.
- `OverlayMode`/`OverlayPhase` exigem macOS 13+ (SwiftUI material); em versões
  anteriores os métodos viram no-op (o app deve degradar para um HUD in-window).

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

## 2026-10-23 — Live transcription, vocabulário, confiança por palavra, modelos, waveform e dispositivos

Estas **mudam a API pública** (todas aditivas/compatíveis com o wire existente). O
app pode adotar aos poucos; nada do que já existia foi renomeado.

- **Transcrição ao vivo.** `startRecording` ganhou `bool liveTranscription = false`.
  Com `true`, o nativo transcreve janelas de ~5 s (sobreposição de ~1 s) com o modelo
  `tiny` numa lane de baixa prioridade separada do `transcribe` principal e emite
  `Stream<LiveTranscript> liveTranscript(String recordingId)` (`{recordingId, text,
  isFinal}`) no EventChannel **único e permanente** `rbnotes_native/live_transcript`
  (filtrado por `recordingId` no Dart, como o `transcription_progress`). `text` é o
  acumulado já **limpo** (a sobreposição é de-duplicada no nativo). `pauseRecording`
  suspende; `stopRecording` emite o evento final com `isFinal=true`. O modelo `tiny` é
  baixado automaticamente se faltar e a transcrição ao vivo **nunca** atrasa a escrita
  dos wavs (janelas são descartadas se a lane ficar ocupada). Idioma fixo `pt`.

- **Vocabulário/contexto.** `transcribe` ganhou `String? initialPrompt`
  (wire `{initialPrompt: String?}`), mapeado para
  `whisper_full_params.initial_prompt`. Útil para nomes próprios/jargão.

- **Confiança por palavra.** `TranscriptSegment` ganhou
  `List<Word>? words` (`Word{text, start, end, probability}`; wire
  `words: [{text, startMs, endMs, probability}]`, **opcional**). Vem de
  `token_timestamps` do whisper.cpp, com os tokens agregados em palavras
  (probabilidade = média das probabilidades dos tokens; tokens especiais são
  descartados). `transcribe` agora sempre preenche `words`; a transcrição ao vivo
  (tiny) não. O formato antigo continua válido (campo novo é opcional no wire).

- **Modelos.** `WhisperModel` agora é
  `{ tiny, smallQ5, medium, largeV3TurboQ5, largeV3 }` (os wire names de `smallQ5`
  e `largeV3TurboQ5` não mudaram). Arquivos/SHA-256/tamanho oficiais fixados para
  `ggml-tiny.bin`, `ggml-medium-q5_0.bin` e `ggml-large-v3-q5_0.bin`. Novo
  `Future<void> deleteModel(WhisperModel)` (remove o arquivo; no-op se ausente).
  `modelState` segue retornando `{downloaded, sizeBytes?}`.

- **Picos de waveform.** Novo
  `Future<List<double>> waveformPeaks(String path, int buckets)` — lê `.wav`/`.m4a`,
  faz downmix mono e devolve o pico (0..1) por bucket, para o player do design.

- **Dispositivos de entrada.** Novo
  `Future<List<AudioInputDevice>> inputDevices()` (`{id, name, isDefault}`, `id` = UID
  CoreAudio) e `startRecording` ganhou `String? inputDeviceId` (null = default do
  sistema). Se o dispositivo escolhido não puder ser selecionado, a gravação continua
  no default e um diagnóstico `audio_config_changed` é emitido.

Notas de wire (para o fake do app):
- `startRecording` agora envia sempre `{id, directory, captureSystemAudio,
  liveTranscription, inputDeviceId}` (os dois últimos com defaults `false`/`null`).
- `transcribe` agora envia sempre `{wavPath, model, language, initialPrompt, priority}`.
- Novos canais/métodos: EventChannel `rbnotes_native/live_transcript`; métodos
  `inputDevices`, `waveformPeaks` (`{path, buckets}`), `deleteModel` (`{model}`).
