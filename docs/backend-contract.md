# Contrato desktop ↔ rbnotes-api (v1)

Base: `https://api.notes.rodolfodebonis.com.br/v1` (dev: `http://localhost:8080/v1`). JSON camelCase. Erros `application/problem+json` com `code`.
Auth: `Authorization: Bearer <access_token>` do realm Keycloak `rbnotes` (issuer `https://auth.rodolfodebonis.com.br/realms/rbnotes`, client público `rbnotes-desktop`, PKCE S256, redirect loopback em **porta fixa** `http://127.0.0.1:53682/callback` (a variante `http://localhost:53682/callback` também é aceita; não use a forma sem porta), scopes `openid profile email offline_access`; audience `rbnotes-api` vem como default scope — **não** pedir).

Fonte da verdade do contrato: `rbnotes-api/api/openapi.yaml`. Este doc é o resumo que o desktop usa para os fakes.

## Sync (offline-first, LWW por `updatedAt`)
- `POST /sync/push` `{ changes: Change[] }` → `{ applied: string[], conflicts: Change[] }`
- `GET /sync/pull?since=<cursor>` → `{ changes: Change[], cursor: string }`
- `Change = { entity: "note"|"segment_set"|"folder"|"action"|"collection"|"vocabulary"|"chat_message"|"note_ai", id: string, updatedAt: ISO8601, deleted: boolean, data: object }`
- Áudio: `PUT /notes/{id}/audio?part=<n>&total=<n>` → `{ part, completed }` (envie a parte 1 primeiro; `completed=true` na última). Corpo `application/octet-stream` ou `audio/*`, com `Content-Length` **obrigatório** (o corpo é transmitido direto ao storage). Chunk **padrão e máximo de 16 MiB**; toda parte **não final** precisa ter **≥ 5 MiB** (só a última pode ser menor). `total` deve ser igual ao do upload em andamento e `part ≤ total`. Reenviar a última parte após concluir é sucesso idempotente. Erros: `409 audio_no_upload|audio_total_mismatch|audio_completed`, `411` (sem Content-Length), `413 chunk_too_large|audio_too_large`, `422 audio_part_too_small|audio_bad_content_type`. `GET /notes/{id}/audio` serve por streaming e aceita `Range: bytes=i-j` (resposta `206` com `Content-Range`; `Accept-Ranges: bytes`; `Content-Type` sempre `audio/mp4` ou o tipo validado). `{id}` restrito a `[A-Za-z0-9_-]`.

## IA (jobs assíncronos via ai-worker / Claude Code headless)
Todos retornam `202 { id, status: "queued" }` — **inclusive `GET /ai/diary/prompt`** (a API não executa a CLI). Resultado em `GET /ai/streams/{id}` (SSE; eventos `status|text|json|tool|ping|done|error`, heartbeat `ping` 5 s, suporta `Last-Event-ID`) e persistido no servidor (as saídas que são entidades — `note_ai`, `chat_message` — voltam no próximo pull). A saída estruturada chega pelos eventos `json` (o objeto cresce incrementalmente; o campo `text` do objeto é o "texto em streaming" do chat/ask). O evento `text` fica reservado.

- `POST /ai/notes/{id}/enrich` body `{ transcript: Segment[], speakers: string[], folder, style: "objetivo"|"detalhado"|"topicos", length: "curto"|"medio"|"longo", model: "sonnet"|"opus"|"haiku", extractTasks: bool }` → JSON `NoteAi`:
  ```json
  { "title": "…", "tldr": "…", "points": ["…"], "quote": { "segmentIndex": 2, "text": "…", "speaker": "Camila", "atMs": 188000 },
    "actions": [{ "text": "…", "owner": "Você", "due": "2026-10-30|null" }],
    "decisions": ["…"], "questions": ["…"],
    "speakerNames": { "others": ["Camila", "Rafael"], "segments": [{ "index": 1, "speaker": "Camila", "inferred": true }] } }
  ```
- `POST /ai/notes/{id}/chat` `{ threadId?, message, transcript?: Segment[] }` → JSON (streaming) `{ text, cites: [{ atMs }] }`. `threadId` ausente = id da nota. Envie `transcript` para ancorar as citações aos `startMs` reais (sem ele, as citações não são filtradas).
- `POST /ai/ask` `{ question }` → JSON (streaming) `{ text, sources: [{ noteId, title }] }` (servidor busca candidatas por FTS pt-BR + recência, máx ~12, e só aceita fontes dentre elas; o `title` é o canônico do servidor).
- `POST /ai/collections/rule` `{ description }` → `{ label, ruleText, rule: { keywords: string[], folders?: string[], minSpeakers?: int, openActions?: bool } }` (o desktop avalia a regra localmente).
- `POST /ai/diary/month` `{ month: "2026-10" }` → `{ summary, themes: [{ name, count }] }` (contexto: notas recentes indexadas do usuário). `GET /ai/diary/prompt?date=` → assíncrono (202 + stream) → `{ prompt }`.

`Segment = { index, speaker: "me"|"others"|<nome>, startMs, endMs, text }`.

Privacidade (no cliente, antes de enviar): notas da pasta Pessoal não vão para `/ai/*` se a preferência estiver ligada; CPF/telefone/cartão mascarados.

Modelos permitidos: `sonnet|opus|haiku` (fora disso → 422). Cota diária por usuário (`AI_DAILY_LIMIT`) → 429 `code: ai_daily_limit`. O cursor do `pull` é um inteiro em string, monotônico por usuário.
