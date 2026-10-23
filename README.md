# RbNotes

App desktop pessoal de **voice notes** para **macOS**, local-first (sem backend):
gravação de mic + áudio do sistema, transcrição local com whisper.cpp, ditado
global e organização com busca full-text.

Construído em Flutter, seguindo os padrões do `spooliq-desktop`
(bloc + get_it + go_router + forma_ui + sentry).

## Recursos (MVP)

- **Gravação**: mic e, opcionalmente, áudio do sistema (reuniões) em canais
  separados; pausar/retomar, medidor por canal e recuperação de gravações
  interrompidas.
- **Transcrição local**: whisper.cpp (Metal) em fila serial de background; junta
  os falantes (`Eu` = mic, `Outros` = sistema) e gera o título automático.
- **Ditado global**: atalho configurável (padrão ⌥Space, segurar-para-falar) →
  transcreve → cola no app em foco → salva como nota; "colar último ditado".
- **Notas**: lista com busca FTS5 (bm25 + trecho destacado), filtro por tag,
  fixadas primeiro e agrupadas por dia; player sincronizado com a transcrição
  (clique no segmento pula no áudio), edição de título, tags com emoji, copiar e
  exportar `.md`/`.txt`.
- **Menu bar** (tray): Gravar/Parar, status e "Abrir RbNotes".
- **Observabilidade**: Sentry (via `--dart-define=SENTRY_DSN`, desligado se
  vazio) e logs estruturados; erros nativos chegam como `RbNativeException` com
  o `code` anexado ao Sentry.

## Pré-requisitos

- macOS 13.0+ (ScreenCaptureKit, whisper Metal).
- [fvm](https://fvm.app) com Flutter **3.47.6** (`.fvmrc`).
- `cmake` + Command Line Tools do Xcode (o whisper.cpp é compilado do fonte):
  `brew install cmake`.
- Token do pub privado (forma_ui):
  `dart pub token add https://pub.rodolfodebonis.com.br`.

## Setup

```sh
fvm install
fvm flutter pub get
```

O plugin nativo mora em `packages/rbnotes_native` (versionado neste repo) e é
referenciado por `path:`. O `macos/Podfile` roda `scripts/build_whisper.sh` do
plugin automaticamente, gerando `whisper.xcframework` (não versionado) antes do
CocoaPods — a primeira build é mais demorada.

## Rodar

```sh
fvm flutter run -d macos -t lib/main_development.dart
# produção (Sentry ligado):
fvm flutter run -d macos -t lib/main_production.dart \
  --dart-define=SENTRY_DSN=https://...
```

## Permissões (System Settings → Privacy & Security)

O app guia o usuário em **Configurações → Permissões**:

1. **Microfone** — gravar e ditar (prompt do sistema).
2. **Gravação de tela** — só para capturar o áudio do sistema; a primeira
   solicitação abre os Ajustes (relançar após conceder).
3. **Acessibilidade** — ditado global (CGEventTap) e colar o texto.

O App Sandbox fica **desligado** (exigência de CGEventTap, Acessibilidade e
ScreenCaptureKit).

## Testes

```sh
fvm flutter analyze
fvm flutter test
```

Cobrem: repositório drift em memória + busca FTS, fila de transcrição e junção
de falantes com `FakeRbNative`, os cubits (gravação, recuperação, lista,
detalhe, configurações), o serviço de ditado, exportação e as telas principais.
Todos usam `FakeRbNative` — nenhum teste depende do plugin nativo real.

## Build

```sh
fvm flutter build macos --debug -t lib/main_production.dart
```

## Arquitetura

```
lib/
  app/            app, shell master-detail, tray, tema
  core/           config, DI (get_it), tema (forma), rotas, paths, observabilidade
  data/database/  drift: notes, transcript_segments, tags, note_tags + FTS5
  native/         fachada do contrato (reexporta rbnotes_native) + FakeRbNative
  features/
    recording/    RecordingCubit, RecoveryCubit, painel de gravação
    transcription/ TranscriptionQueue (fila serial), ModelDownloadCubit, lógica
    notes/         NoteRepository, lista, detalhe (player), modelos, export
    dictation/     DictationService (atalho → transcreve → cola → salva)
    settings/      SettingsStore, SettingsCubit, editor de atalho
```

Toda a lógica depende da interface `RbNative` (`package:rbnotes_native`),
injetada via get_it; os testes injetam `FakeRbNative`.
