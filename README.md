# RbNotes

App desktop pessoal de **voice notes** para **macOS**, local-first: gravação de
mic + áudio do sistema, transcrição local com whisper.cpp, ditado global,
resumo/insights por IA e organização com busca full-text. A UI segue o
**design v3** (Claude Design) — papel quente, acento `#E0512E`, títulos serif
(Newsreader/New York) e corpo em SF Pro.

Construído em Flutter (bloc + get_it + forma_ui + sentry), com o plugin nativo
`packages/rbnotes_native` (Swift: ScreenCaptureKit, whisper.cpp/Metal, ditado).

## Recursos

- **Login** (e-mail/senha + Google; Apple "em breve") e **onboarding** em 4
  passos (boas-vindas, permissões, modelo Whisper com download, pronto).
- **Shell de 3 colunas**: sidebar (Todas/Favoritas/Diário, pastas com cor,
  coleções inteligentes, status Whisper/Claude, perfil), lista agrupada por dia
  com busca FTS, e detalhe.
- **Nota**: player com waveform/velocidade e as abas **Resumo** (TL;DR, pontos,
  citação "ouvir em"), **Transcrição** (falantes com cor, palavra de baixa
  confiança → "Corrigir palavra" em todas as notas + vocabulário), **Insights**
  (ações, decisões, em aberto) e **Conversa** (chat com citações de tempo).
- **Perguntar às notas** (⌘K, streaming + fontes), **Tarefas esquecidas**
  (> 3 dias), **Reuniões** (> 1 falante), **coleções por linguagem natural**,
  **Diário** (pergunta do dia, calendário com sequência, resumo do mês, Touch ID).
- **Gravação**: HUD com onda e transcrição ao vivo → HUD de processamento
  (Whisper → falantes → Claude) → título "digitando". Ditado global (⌥Space).
- **Configurações** (⌘,) com 7 abas; **atalhos** ⌘R/⌘K/⌘,/espaço/Esc.
- **Observabilidade**: Sentry (via `--dart-define=SENTRY_DSN`).

## IA, sync e privacidade

Auth, sync e IA são **interfaces** (`AuthService`, `SyncClient`, `AiClient`) com
duas implementações, escolhidas por flavor/`--dart-define`:

- **Local-first (fakes)** — padrão em `development`. `FakeAiClient` gera
  respostas plausíveis e streaming simulado; `FakeSyncClient`/`FakeAuthService`
  não tocam rede. Bom para desenvolver a UI sem backend.
- **Integrado (`rbnotes-api`)** — padrão em `production` (ou
  `--dart-define=RBNOTES_USE_BACKEND=true`):
  - **Auth**: OIDC Authorization Code + **PKCE S256** contra o realm Keycloak
    `rbnotes` (client público `rbnotes-desktop`), via navegador do sistema e um
    servidor **loopback** em `127.0.0.1:53682` só durante o login (state +
    nonce verificados, timeout 5 min). Google = `kc_idp_hint=google`;
    e-mail/senha abre o Keycloak com `login_hint`; cadastro abre a página de
    `registrations`. Tokens no **Keychain**; o refresh **rotaciona**
    (single-flight). Logout via `end_session`. `403 not_allowed` → aviso e
    logout.
  - **Sync** (`/sync/push|pull`): offline-first LWW por `updatedAt`, cursor
    persistido, mapeamento completo das 8 entidades do contrato (note,
    segment_set, folder, action, collection, vocabulary, chat_message, note_ai),
    backoff exponencial e status ao vivo na aba Conta. Dispara ao abrir, a cada
    2 min, após criar nota (debounce) e no "Sincronizar agora".
  - **Áudio** (`/notes/{id}/audio`): upload em partes de 16 MiB (não-final ≥ 5
    MiB, parte 1 primeiro) com fila e retomada; download sob demanda com `Range`.
  - **IA** (`/ai/*`): `202 + id` e resultado por **SSE** (`GET /ai/streams/{id}`)
    com reconexão por `Last-Event-ID`; `429 ai_daily_limit` reflete no card
    "Claude".

Antes de enviar texto à IA: a pasta Pessoal pode ser omitida e CPF/telefone/
cartão são mascarados (`PrivacyMasker`).

### Backend / configuração

```sh
# dev apontando para o backend local (precisa do rbnotes-api em :8080):
fvm flutter run -d macos -t lib/main_development.dart \
  --dart-define=RBNOTES_USE_BACKEND=true \
  --dart-define=RBNOTES_API_BASE_URL=http://localhost:8080/v1
```

`--dart-define` disponíveis: `RBNOTES_USE_BACKEND`, `RBNOTES_API_BASE_URL`,
`RBNOTES_AUTH_ISSUER`, `RBNOTES_AUTH_CLIENT_ID`, `RBNOTES_AUTH_REDIRECT_URI`,
`SENTRY_DSN`. Divergências/limitações de contrato: `docs/INTEGRATION_NOTES.md`.

## Pré-requisitos

- macOS 13.0+; [fvm](https://fvm.app) com Flutter **3.47.6** (`.fvmrc`).
- `brew install cmake` (whisper.cpp compilado do fonte).
- Token do pub privado: `dart pub token add https://pub.rodolfodebonis.com.br`.

## Rodar

```sh
fvm install && fvm flutter pub get
cd macos && pod install && cd ..   # necessário quando o plugin nativo muda
fvm flutter run -d macos -t lib/main_development.dart
```

A primeira execução semeia os dados do design (notas, resumos, diário) para a UI
refletir os mockups.

## Testes e qualidade

```sh
fvm flutter analyze                      # limpo
fvm flutter test                         # inclui golden tests (1280×800)
fvm flutter test --update-goldens        # regenera os goldens
fvm flutter build macos --debug -t lib/main_development.dart
```

Goldens em `test/features/**/goldens/` (login claro/escuro, shell claro/escuro,
transcrição, insights, conversa, diário, tarefas, perguntar, configurações).
Testes cobrem migração drift v2→v3, masker, regras de coleção, tarefas
esquecidas, sequência do diário, streaming fake, os cubits novos e os atalhos.

## Arquitetura

```
lib/
  app/            RbNotesApp, RootView, shell de 3 colunas + overlays/HUDs, tray
  core/           config, DI (get_it), tema/tokens (RbTokens), ui, observabilidade
  data/database/  drift v3: notes, segments, folders, note_ai, actions,
                  chat_messages, collections, vocabulary, diary*, sync_meta + FTS5
  native/         fachada do contrato (reexporta rbnotes_native) + FakeRbNative
  features/
    auth/         AuthService + Fake, login/onboarding
    library/      sidebar, lista, coleções, demo seeder
    notes/        repositórios, detalhe (player, abas), NoteViewCubit
    recording/    RecordingCubit (live + processamento), HUDs, recuperação
    transcription/ fila serial, junção de falantes, palavras/confiança
    ai/           AiClient + FakeAiClient, EnrichmentService, masker, Ask
    collections/  regras de coleção, tarefas esquecidas
    diary/        repositório, calendário/sequência, DiaryCubit
    dictation/    ditado global (atalho → transcreve → cola → salva)
    settings/     SettingsStore (7 abas), vocabulário
```

Toda a lógica depende de interfaces (`RbNative`, `AiClient`, `SyncClient`,
`AuthService`), injetadas via get_it; os testes injetam fakes.
