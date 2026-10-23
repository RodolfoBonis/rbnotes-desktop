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
  login, com `state`+`nonce` verificados e timeout de 5 min.
- **Refresh rotaciona** (`revoke_refresh_token`): o novo par é sempre salvo no
  Keychain; o refresh é single-flight (sem renovações concorrentes).
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
  pull não causa conflito. `sync_meta` segue disponível para um dirty-tracking
  mais fino no futuro.
- Conflitos devolvidos pelo servidor são aplicados localmente (a versão do
  servidor vence). Cursor persistido em `SharedPreferences`.

### IA
- Todo pedido é assíncrono (`202 + id`) e o resultado vem por SSE
  (`GET /ai/streams/{id}`), inclusive o disparador diário (`GET /ai/diary/prompt`
  também responde 202 — ver `CHANGES.md` item 2). O objeto estruturado cresce
  nos eventos `json`; o `text` é o streaming do chat/ask.
- Reconexão por `Last-Event-ID` e timeout de heartbeat (sem `ping` por N s →
  reconecta). `429 ai_daily_limit` → `AiDailyLimitException` e card "Claude" em
  "Limite diário atingido".
- O `model` enviado vem da preferência de Inteligência (`Claude Sonnet/Opus/
  Haiku` → `sonnet|opus|haiku`); se não mapear, é omitido (backend usa
  `AI_MODEL`).

## Limitações conhecidas / follow-ups

1. **segment_set sem timestamp próprio** — a tabela `transcript_segments` não
   tem `updatedAt`. O `segment_set` é empurrado junto quando o `updatedAt` da
   nota muda. No fluxo normal isso basta (ao transcrever, a nota é tocada:
   `setStatus`/`updateTitle`/`setAiStatus` bumpam `updatedAt`). Uma edição de
   segmento que **não** toque a nota só sincroniza no próximo toque da nota.
   Follow-up: bumpar `note.updatedAt` em `replaceSegments`/`fixWord`.
2. **Fila de upload de áudio não é auto-enfileirada** pelo pipeline de gravação
   ainda. A `AudioUploadQueue` (persistente, com retomada e backoff) e o
   `AudioSync` (chunks + download com Range) estão prontos e testados, mas falta
   o gancho `queue.enqueue(noteId, path)` ao finalizar a transcrição e a
   coordenação com "Apagar áudio após transcrever"/retenção (subir antes de
   apagar). Hoje a fila sobe o que estiver em disco e descarta itens cujo
   arquivo sumiu.
3. **Gatilho de sync após mudanças locais** está ligado na criação de nota
   (debounce via `requestSync`). Outras edições dependem da cadência de 2 min e
   do "Sincronizar agora". Follow-up: chamar `requestSync` nos demais pontos de
   escrita (repos) ou observar o drift.
4. **Download de áudio sob demanda** (outro Mac) existe em `AudioSync.
   downloadToFile` (com Range/retomada), mas ainda não está ligado ao
   `AudioPlayerController` para buscar quando o arquivo local não existe.

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
> single-flight com rotação, ApiClient (problem+json), sync (mapeamento, cursor,
> conflito, backoff), upload de áudio e SSE usando um `HttpServer` loopback
> local como fake do backend.
