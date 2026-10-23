# Integração desktop ↔ rbnotes-api — notas

Registro das decisões, limitações conhecidas e pontos que só dá para validar
depois do deploy. A fonte da verdade do contrato é `rbnotes-api/api/openapi.yaml`
(resumo em `docs/backend-contract.md`).

## Decisões

### Auth (OIDC Authorization Code + PKCE)
- **Formulário de e-mail/senha** — o design tem campos Nome/E-mail/Senha e um
  botão "Entrar". Como o client é **público com PKCE** (sem password grant), o
  botão **abre o Keycloak no navegador** levando o e-mail digitado em
  `login_hint` (o usuário digita a senha na página do realm). É o mais fiel
  possível ao design sem trafegar a senha pelo app nem abrir mão da segurança.
  "Criar conta" abre a página de `registrations` do Keycloak com o mesmo fluxo.
  O botão Google usa `kc_idp_hint=google`.
- **Redirect loopback fixo** `http://127.0.0.1:53682/callback` (porta fixa
  porque o client registra um redirect exato). O servidor sobe só durante o
  login, escuta **apenas** em `127.0.0.1`, com `state`+`nonce` verificados e
  timeout de 5 min. Se o navegador não abrir, o socket é fechado na hora (não
  fica ouvindo até o timeout).
- **Refresh rotaciona** (`revoke_refresh_token`): o novo par é sempre salvo no
  Keychain; o refresh é single-flight (sem renovações concorrentes). Uma falha
  **de rede** no refresh **não** derruba a sessão nem apaga o refresh token —
  só um refresh inválido/revogado (erro do provider) encerra a sessão.
- **`403 not_allowed`** (allowlist do backend) → `AuthException`/`AccessRevoked`,
  aviso "Esta conta não tem acesso ao RbNotes" e logout.

### Sync
- O servidor guarda `Change.data` opaco (só lê `note.data.title` para o índice),
  então o desktop define a **forma canônica camelCase** das 8 entidades
  (`lib/features/sync/data/sync_mappers.dart`), com testes de round-trip.
- **Caminhos de áudio locais** (`playbackPath`/`micWavPath`/`systemWavPath`)
  **não** vão no `data` — são por-dispositivo; o áudio sincroniza por
  `/notes/{id}/audio`.
- **"O que mudou" por marca d'água**: o push coleta linhas com
  `updatedAt > watermark` (persistida), em vez de usar `sync_meta.dirty`. É
  correto porque reenviar uma linha idêntica (mesmo `updatedAt`+`data`) é
  **idempotente** no servidor, então um eventual eco de algo recém-aplicado no
  pull não causa conflito.
- **`segment_set` tem marca d'água própria** no `sync_meta` (`entity =
  'segment_set'`), independente de `note.updatedAt`. `NoteRepository`
  (`replaceSegments`/`fixWord`) bumpa essa marca a cada edição de segmentos, e o
  `SyncLocalStore` a usa no push (coleta) e no LWW (aplicação). Assim: (a) uma
  edição só de segmentos sincroniza mesmo sem tocar a nota; (b) uma edição da
  nota em outro dispositivo **não** arrasta segmentos stale por cima de uma
  versão mais nova — convergência LWW correta.
- **Gatilho de sync em toda mutação local**: o `SyncTrigger` observa as escritas
  do drift (`tableUpdates`) nas 8 tabelas sincronizáveis e chama `requestSync`
  (debounced) em qualquer mudança relevante (título, pasta, favorito, ações,
  coleções, vocabulário, chat, note_ai, segmentos, exclusões). Centraliza o
  gatilho num ponto só, sem espalhar `requestSync()` pelos repositórios nem
  depender da cadência de 2 min. `sync_meta`/FTS/tags ficam de fora para não
  gerar sync espúrio.
- Conflitos devolvidos pelo servidor são aplicados localmente (a versão do
  servidor vence). Cursor persistido em `SharedPreferences`.

### Áudio
- **Upload após a transcrição**: ao terminar de transcrever (fluxo normal ou
  recuperação de crash — ambos emitem `done`), o `AudioUploadCoordinator`
  enfileira o `.m4a` na `AudioUploadQueue` (se o sync estiver ligado). A fila é
  persistente, com retomada no boot e backoff.
- **Coordenação com "Apagar áudio após transcrever"**: o arquivo local só é
  apagado **depois** do upload concluído (a própria fila remove e zera os
  caminhos ao terminar) quando o sync está ligado; com o sync desligado, o
  `RetentionService` apaga na hora. A varredura de retenção, com sync ligado e
  delete-after, enfileira o áudio pendente em vez de apagá-lo antes de subir.
- **Download sob demanda**: quando a nota não tem áudio local (veio de outro
  Mac, ou o `.m4a` foi apagado localmente), o player baixa via
  `GET /notes/{id}/audio` com `Range` para `audio_cache/` (em blocos, com
  progresso e retomada). Uma vez em cache, toca offline. `404` vira o aviso
  "Áudio não disponível.".

### IA
- Todo pedido é assíncrono (`202 + id`) e o resultado vem por SSE
  (`GET /ai/streams/{id}`), inclusive o disparador diário (`GET /ai/diary/prompt`
  também responde 202 — ver `CHANGES.md` item 2). O objeto estruturado cresce
  nos eventos `json`; o `text` é o streaming do chat/ask.
- Reconexão por `Last-Event-ID` e timeout de heartbeat (sem `ping` por N s →
  reconecta), **limitada** a `maxRetries` (sem reconexão infinita). `429
  ai_daily_limit` → `AiDailyLimitException` e card "Claude" em "Limite diário
  atingido".
- O `model` enviado vem da preferência de Inteligência (`Claude Sonnet/Opus/
  Haiku` → `sonnet|opus|haiku`); se não mapear, é omitido (backend usa
  `AI_MODEL`).

## Follow-ups fechados

Os quatro follow-ups abaixo foram implementados (cada um com teste); o texto
acima descreve o comportamento final.

1. ✅ **segment_set com timestamp próprio** — resolvido via marca d'água no
   `sync_meta` (melhor que bumpar `note.updatedAt`, que arrastaria segmentos
   stale entre dispositivos). Teste: `segment_set_convergence_test.dart`.
2. ✅ **Fila de upload auto-enfileirada** — `AudioUploadCoordinator` no fim da
   transcrição + coordenação retenção/delete-after. Testes:
   `audio_upload_coordinator_test.dart`, `retention_service_test.dart`.
3. ✅ **Gatilho de sync em toda edição** — `SyncTrigger` sobre `tableUpdates`.
   Teste: `sync_trigger_test.dart`.
4. ✅ **Download de áudio sob demanda** — ligado ao `NoteViewCubit` com
   progresso, cache offline e 404. Testes: `note_audio_download_test.dart`,
   `audio_sync_test.dart`.

## Divergências de contrato encontradas

Nenhuma divergência que contradiga o `openapi.yaml`. O único ponto que poderia
surpreender — `GET /ai/diary/prompt` ser assíncrono (202) — já está registrado
em `rbnotes-api/api/CHANGES.md` (item 2) e é tratado pelo cliente.

## Só dá para validar depois do deploy

- **Login real no Keycloak** (realm `rbnotes`, brokered Google, allowlist de
  e-mail) e o fluxo loopback no navegador do sistema.
- **Sync entre dois Macs** (convergência LWW, cursor, conflitos reais).
- **SSE real** do `ai-worker` (Claude Code headless) e os formatos exatos dos
  eventos `json` por tipo de job.
- **Upload/download de áudio** contra o MinIO (multipart S3, limites, Range).

> Não foi possível rodar um E2E local contra a `rbnotes-api`: a API exige
> Postgres + Redis + MinIO e **não há `postgres`/`redis-server` no Homebrew**
> desta máquina (nem Docker garantido). Os testes cobrem auth/PKCE, refresh
> single-flight com rotação (inclusive falha de rede preservando a sessão),
> ApiClient (problem+json), sync (mapeamento, cursor, conflito, backoff,
> convergência de segment_set, gatilho por mutação), upload de áudio (enfileirar
> + delete-after), download com Range/progresso/404 e SSE usando um `HttpServer`
> loopback local como fake do backend.
