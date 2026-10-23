# Contrato desktop ↔ rbnotes-api (v1)

Base: `https://api.notes.rodolfodebonis.com.br/v1` (dev: `http://localhost:8080/v1`). JSON camelCase. Erros `application/problem+json` com `code`.
Auth: `Authorization: Bearer <access_token>` do realm Keycloak `rbnotes` (issuer `https://auth.rodolfodebonis.com.br/realms/rbnotes`, client público `rbnotes-desktop`, PKCE S256, redirect loopback `http://127.0.0.1:<porta>/callback`, scopes `openid profile email offline_access`; audience `rbnotes-api` vem como default scope — **não** pedir).

Fonte da verdade do contrato: `rbnotes-api/api/openapi.yaml`. Este doc é o resumo que o desktop usa para os fakes.

## Sync (offline-first, LWW por `updatedAt`)
- `POST /sync/push` `{ changes: Change[] }` → `{ applied: string[], conflicts: Change[] }`
- `GET /sync/pull?since=<cursor>` → `{ changes: Change[], cursor: string }`
- `Change = { entity: "note"|"segment_set"|"folder"|"action"|"collection"|"vocabulary"|"chat_message"|"note_ai", id: string, updatedAt: ISO8601, deleted: boolean, data: object }`
- Áudio (opcional): `PUT /notes/{id}/audio?part=<n>&total=<n>` (chunks ≤ 50 MB, `application/octet-stream`), `GET /notes/{id}/audio`.

## IA (jobs assíncronos via ai-worker / Claude Code headless)
Todos retornam `202 { id, status: "queued" }`; resultado em `GET /ai/streams/{id}` (SSE; eventos `status|text|json|done|error`, heartbeat `ping` 5 s, suporta `Last-Event-ID`) e persistido no servidor (vem no próximo pull).

- `POST /ai/notes/{id}/enrich` body `{ transcript: Segment[], speakers: string[], folder, style: "objetivo"|"detalhado"|"topicos", length: "curto"|"medio"|"longo", model: "sonnet"|"opus"|"haiku", extractTasks: bool }` → JSON `NoteAi`:
  ```json
  { "title": "…", "tldr": "…", "points": ["…"], "quote": { "segmentIndex": 2, "text": "…", "speaker": "Camila", "atMs": 188000 },
    "actions": [{ "text": "…", "owner": "Você", "due": "2026-10-30|null" }],
    "decisions": ["…"], "questions": ["…"],
    "speakerNames": { "others": ["Camila", "Rafael"], "segments": [{ "index": 1, "speaker": "Camila", "inferred": true }] } }
  ```
- `POST /ai/notes/{id}/chat` `{ threadId?, message }` → texto em streaming + JSON final `{ text, cites: [{ atMs }] }`.
- `POST /ai/ask` `{ question }` → texto em streaming + JSON final `{ text, sources: [{ noteId, title }] }` (servidor busca candidatas por FTS e manda só elas ao Claude).
- `POST /ai/collections/rule` `{ description }` → `{ label, ruleText, rule: { keywords: string[], folders?: string[], minSpeakers?: int, openActions?: bool } }` (o desktop avalia a regra localmente).
- `POST /ai/diary/month` `{ month: "2026-10" }` → `{ summary, themes: [{ name, count }] }`; `GET /ai/diary/prompt?date=` → `{ prompt }`.

`Segment = { index, speaker: "me"|"others"|<nome>, startMs, endMs, text }`.

Privacidade (no cliente, antes de enviar): notas da pasta Pessoal não vão para `/ai/*` se a preferência estiver ligada; CPF/telefone/cartão mascarados.
