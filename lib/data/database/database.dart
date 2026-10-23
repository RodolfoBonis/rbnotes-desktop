import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Estado de ciclo de vida de uma nota.
enum NoteStatus { recording, transcribing, ready, failed }

/// Origem da nota.
enum NoteSource { recording, dictation }

/// Tipo de gravação: nota comum ou entrada de diário (fluxo e privacidade
/// diferentes — ver design v3, `recKind`).
enum NoteKind { note, diary }

/// Estado do enriquecimento por IA (resumo/insights/título).
enum AiStatus { none, pending, ready, failed }

/// Falante de um segmento (mic = eu, sistema = outros).
enum SegmentSpeaker { me, others }

/// Papel de uma mensagem do chat da nota.
enum ChatRole { user, ai }

@DataClassName('NoteRow')
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  TextColumn get playbackPath => text().nullable()();
  TextColumn get micWavPath => text().nullable()();
  TextColumn get systemWavPath => text().nullable()();
  TextColumn get status => textEnum<NoteStatus>()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get source => textEnum<NoteSource>()();

  // ---- v3 ----
  /// Pasta da nota (`folders.id`). Diário usa `'diario'`. Null = sem pasta.
  TextColumn get folderId => text().nullable()();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  TextColumn get kind =>
      textEnum<NoteKind>().withDefault(const Constant('note'))();

  /// Título gerado automaticamente pela IA (mostra o chip "Título gerado").
  BoolColumn get autoTitle => boolean().withDefault(const Constant(false))();
  TextColumn get aiStatus =>
      textEnum<AiStatus>().withDefault(const Constant('none'))();

  /// Nomes dos falantes, serializados (`["Você","Camila"]`); null até a IA
  /// inferir. A grade completa (índice→nome, inferido) fica em `note_ai`.
  TextColumn get speakersJson => text().nullable()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SegmentRow')
class TranscriptSegments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get speaker => textEnum<SegmentSpeaker>()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
  TextColumn get content => text()();

  /// Palavras com tempo e confiança (JSON `[{text,startMs,endMs,prob}]`), ou
  /// null quando o nativo não computou timestamps por palavra. Usado para
  /// sublinhar palavras de baixa confiança (fluxo "Corrigir palavra").
  TextColumn get wordsJson => text().nullable()();
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get emoji => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('NoteTagRow')
class NoteTags extends Table {
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId =>
      text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {noteId, tagId};
}

/// Pastas do usuário (cores e contagem na sidebar). Seed v3:
/// Trabalho/Pessoal/Estudos/Ideias/Diário.
@DataClassName('FolderRow')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get colorHex => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Diário fica oculto da lista de pastas (tem sua própria seção).
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Enriquecimento por IA de uma nota (JSON `NoteAi` do contrato), 1:1 com a
/// nota. Guardado como blob para acompanhar o contrato sem explodir em colunas.
@DataClassName('NoteAiRow')
class NoteAiTable extends Table {
  @override
  String get tableName => 'note_ai';

  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get json => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {noteId};
}

/// Ações extraídas da nota (Insights) e que alimentam "Tarefas esquecidas".
@DataClassName('ActionRow')
class Actions extends Table {
  TextColumn get id => text()();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get content => text()();
  TextColumn get owner => text().nullable()();
  DateTimeColumn get due => dateTime().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get snoozedUntil => dateTime().nullable()();
  BoolColumn get dismissed => boolean().withDefault(const Constant(false))();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Mensagens do chat "Conversa" de uma nota.
@DataClassName('ChatMessageRow')
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get noteId =>
      text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => textEnum<ChatRole>()();
  TextColumn get content => text()();

  /// Citações de tempo (lista de ms em JSON), para os chips "ouvir em …".
  TextColumn get citesJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Coleções inteligentes (regra em JSON, avaliada localmente).
@DataClassName('CollectionRow')
class Collections extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get ruleText => text()();

  /// Regra estruturada: `{keywords, folders?, minSpeakers?, openActions?}`.
  TextColumn get ruleJson => text()();

  /// Coleção embutida com lógica especial (ex.: `'tasks'`), ou null.
  TextColumn get kind => text().nullable()();
  BoolColumn get builtin => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Vocabulário do Whisper (`initial_prompt`) — nomes/termos a reconhecer.
@DataClassName('VocabularyRow')
class Vocabulary extends Table {
  TextColumn get id => text()();
  TextColumn get term => text()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Perguntas do diário (pergunta do dia + "outra pergunta").
@DataClassName('DiaryPromptRow')
class DiaryPrompts extends Table {
  TextColumn get id => text()();
  TextColumn get question => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Entradas de diário por dia (para o calendário e a sequência).
@DataClassName('DiaryEntryRow')
class DiaryEntries extends Table {
  /// Dia no formato `yyyy-MM-dd`.
  TextColumn get day => text()();
  TextColumn get noteId => text().nullable()();
  TextColumn get promptId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {day};
}

/// Estado de sync por entidade (LWW por `updatedAt`), para o push/pull futuro.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  @override
  String get tableName => 'sync_meta';

  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Mudou localmente e ainda não foi empurrado para o servidor.
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {entity, entityId};
}

/// Linha de resultado da busca FTS: nota + trecho destacado + ranking bm25.
class NoteSearchHit {
  const NoteSearchHit({
    required this.note,
    required this.snippet,
    required this.rank,
  });

  final NoteRow note;
  final String snippet;
  final double rank;
}

/// Índice FTS5 cujo `rowid` espelha o `rowid` de `notes`.
const _createFtsTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  title, body,
  tokenize = 'unicode61 remove_diacritics 2'
)''';

const _ftsTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, '');
END''',
  '''
CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  DELETE FROM notes_fts WHERE rowid = old.rowid;
END''',
  '''
CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE OF title ON notes BEGIN
  UPDATE notes_fts SET title = new.title WHERE rowid = new.rowid;
END''',
];

const _legacyFtsTriggers = <String>[
  'notes_ai',
  'notes_ad',
  'notes_au',
  'seg_ai',
  'seg_au',
  'seg_ad',
];

const _recomposeBodySql = '''
UPDATE notes_fts
SET body = (
  SELECT COALESCE(group_concat(content, ' '), '')
  FROM transcript_segments WHERE note_id = ?1
)
WHERE rowid = (SELECT rowid FROM notes WHERE id = ?1)''';

const _rebuildIndexSql = '''
INSERT INTO notes_fts(rowid, title, body)
SELECT n.rowid, n.title, COALESCE((
  SELECT group_concat(s.content, ' ')
  FROM transcript_segments s WHERE s.note_id = n.id
), '')
FROM notes n''';

const _searchSql = '''
SELECT n.*,
       bm25(notes_fts, 10.0, 1.0) AS rank,
       snippet(notes_fts, 1, '[', ']', '…', 12) AS snippet_body,
       snippet(notes_fts, 0, '[', ']', '…', 12) AS snippet_title
FROM notes_fts JOIN notes n ON n.rowid = notes_fts.rowid
WHERE notes_fts MATCH ?
ORDER BY n.pinned DESC, rank''';

/// Pastas semente (ids batem com `RbTokens.folderColors` e o design).
const seedFolders = <(String, String, String, int, bool)>[
  ('trabalho', 'Trabalho', '#2F6BEB', 0, false),
  ('pessoal', 'Pessoal', '#1E8C5A', 1, false),
  ('estudos', 'Estudos', '#B7791F', 2, false),
  ('ideias', 'Ideias', '#D9472B', 3, false),
  ('diario', 'Diário', '#8A7A66', 4, true),
];

/// Perguntas do diário (design v3, `PROMPTS`).
const seedDiaryPrompts = <String>[
  'O que te deixou com energia hoje?',
  'O que você faria diferente amanhã?',
  'Pelo que você é grato hoje?',
  'O que ocupou sua cabeça hoje?',
];

@DriftDatabase(
  tables: [
    Notes,
    TranscriptSegments,
    Tags,
    NoteTags,
    Folders,
    NoteAiTable,
    Actions,
    ChatMessages,
    Collections,
    Vocabulary,
    DiaryPrompts,
    DiaryEntries,
    SyncMeta,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Para testes: injete um `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearchIndex();
      await _seedV3();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        for (final name in _legacyFtsTriggers) {
          await customStatement('DROP TRIGGER IF EXISTS $name');
        }
        await customStatement('DROP TABLE IF EXISTS notes_fts');
        await _createSearchIndex();
        await rebuildSearchIndex();
      }
      // Reparo de schema genérico (schema v4): compara cada tabela declarada no
      // drift com o `PRAGMA table_info` real e adiciona as colunas que faltam e
      // cria as tabelas que faltam. Conserta bancos vindos do MVP (v1/v2) e
      // tambem bancos ja em v3 que nunca ganharam
      // `transcript_segments.words_json` — a migracao v3 original so mexia em
      // `notes`, entao todo `replaceSegments` falhava e a nota travava em
      // "Resumo em preparacao...".
      await _repairSchema(m);
      if (from < 3) {
        await _seedV3();
      }
    },
  );

  /// Reparo de schema generico (ver [migration]). Idempotente: so adiciona o
  /// que falta. Cobre todas as tabelas declaradas em `@DriftDatabase` (o indice
  /// FTS virtual e tratado a parte em [_createSearchIndex]). Todas as colunas
  /// passiveis de adicao sao nulas ou tem default, compativeis com o
  /// `ALTER TABLE ADD COLUMN` do SQLite.
  Future<void> _repairSchema(Migrator m) async {
    final existingTables = await _tables();
    for (final table in allTables) {
      final name = table.actualTableName;
      if (!existingTables.contains(name)) {
        await m.createTable(table);
        continue;
      }
      final cols = await _columns(name);
      for (final column in table.$columns) {
        if (!cols.contains(column.name)) {
          await m.addColumn(table, column);
        }
      }
    }
  }

  Future<void> _createSearchIndex() async {
    await customStatement(_createFtsTable);
    for (final sql in _ftsTriggers) {
      await customStatement(sql);
    }
  }

  /// Colunas existentes de [table] (para migração defensiva).
  Future<Set<String>> _columns(String table) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  /// Tabelas existentes (para migração defensiva).
  Future<Set<String>> _tables() async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    ).get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  /// Semeia pastas e perguntas do diário (idempotente).
  Future<void> _seedV3() async {
    final now = DateTime.now();
    await batch((b) {
      for (final (id, name, color, order, hidden) in seedFolders) {
        b.insert(
          folders,
          FoldersCompanion.insert(
            id: id,
            name: name,
            colorHex: color,
            sortOrder: Value(order),
            hidden: Value(hidden),
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
      for (var i = 0; i < seedDiaryPrompts.length; i++) {
        b.insert(
          diaryPrompts,
          DiaryPromptsCompanion.insert(
            id: 'prompt_$i',
            question: seedDiaryPrompts[i],
            sortOrder: Value(i),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  Future<void> recomposeSearchBody(String noteId) async {
    await customStatement(_recomposeBodySql, [noteId]);
  }

  Future<void> rebuildSearchIndex() async {
    await transaction(() async {
      await customStatement('DELETE FROM notes_fts');
      await customStatement(_rebuildIndexSql);
    });
  }

  static String? buildMatchQuery(String raw) {
    final terms = raw
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), ''))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"*');
    if (terms.isEmpty) return null;
    return terms.join(' ');
  }

  Future<List<NoteSearchHit>> search(String query) async {
    final match = buildMatchQuery(query);
    if (match == null) return [];
    final rows = await customSelect(
      _searchSql,
      variables: [Variable<String>(match)],
      readsFrom: {notes, transcriptSegments},
    ).get();
    return rows.map((row) {
      final body = row.read<String>('snippet_body');
      final title = row.read<String>('snippet_title');
      return NoteSearchHit(
        note: notes.map(row.data),
        snippet: body.contains('[') ? body : title,
        rank: row.read<double>('rank'),
      );
    }).toList();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'rbnotes', 'rbnotes.sqlite'));
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(file);
  });
}
