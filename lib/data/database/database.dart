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

/// Falante de um segmento (mic = eu, sistema = outros).
enum SegmentSpeaker { me, others }

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

/// Índice FTS5 cujo `rowid` espelha o `rowid` de `notes`. Sem a coluna
/// `note_id UNINDEXED`: o join de volta usa `rowid`, e o corpo (`body`) é
/// recomposto numa única passada por nota (ver
/// [AppDatabase.recomposeSearchBody]), em vez de um `group_concat` por segmento
/// inserido (custo quadrático na transcrição).
const _createFtsTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  title, body,
  tokenize = 'unicode61 remove_diacritics 2'
)''';

/// Gatilhos mínimos: criar/apagar a linha do índice e refletir o título.
/// O corpo (transcrição) é mantido por [AppDatabase.recomposeSearchBody], nunca
/// por gatilhos em `transcript_segments`.
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

/// Nomes de gatilhos (v1 e v2) a derrubar antes de recriar o índice.
const _legacyFtsTriggers = <String>[
  'notes_ai',
  'notes_ad',
  'notes_au',
  'seg_ai',
  'seg_au',
  'seg_ad',
];

/// Recompõe o corpo do índice de uma nota a partir dos seus segmentos atuais.
const _recomposeBodySql = '''
UPDATE notes_fts
SET body = (
  SELECT COALESCE(group_concat(content, ' '), '')
  FROM transcript_segments WHERE note_id = ?1
)
WHERE rowid = (SELECT rowid FROM notes WHERE id = ?1)''';

/// Repopula todo o índice a partir de `notes` + `transcript_segments`.
const _rebuildIndexSql = '''
INSERT INTO notes_fts(rowid, title, body)
SELECT n.rowid, n.title, COALESCE((
  SELECT group_concat(s.content, ' ')
  FROM transcript_segments s WHERE s.note_id = n.id
), '')
FROM notes n''';

/// `snippet` do corpo (coluna 1) e do título (coluna 0). Quando o match está só
/// no título, o trecho do corpo não traz destaque (`[`), então o app usa o do
/// título como fallback (ver [AppDatabase.search]).
const _searchSql = '''
SELECT n.*,
       bm25(notes_fts, 10.0, 1.0) AS rank,
       snippet(notes_fts, 1, '[', ']', '…', 12) AS snippet_body,
       snippet(notes_fts, 0, '[', ']', '…', 12) AS snippet_title
FROM notes_fts JOIN notes n ON n.rowid = notes_fts.rowid
WHERE notes_fts MATCH ?
ORDER BY n.pinned DESC, rank''';

@DriftDatabase(tables: [Notes, TranscriptSegments, Tags, NoteTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Para testes: injete um `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearchIndex();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (m, from, to) async {
      // v2: FTS reestruturado (rowid = notes.rowid, sem gatilhos por segmento).
      // Derruba o índice/gatilhos antigos e reconstrói do zero.
      if (from < 2) {
        for (final name in _legacyFtsTriggers) {
          await customStatement('DROP TRIGGER IF EXISTS $name');
        }
        await customStatement('DROP TABLE IF EXISTS notes_fts');
        await _createSearchIndex();
        await rebuildSearchIndex();
      }
    },
  );

  /// Cria a tabela FTS5 (título + transcrição) e os gatilhos mínimos.
  Future<void> _createSearchIndex() async {
    await customStatement(_createFtsTable);
    for (final sql in _ftsTriggers) {
      await customStatement(sql);
    }
  }

  /// Recompõe o corpo do índice FTS de [noteId] a partir dos seus segmentos.
  /// Chamado uma vez por `NoteRepository.replaceSegments`, na transação.
  Future<void> recomposeSearchBody(String noteId) async {
    await customStatement(_recomposeBodySql, [noteId]);
  }

  /// Reconstrói todo o índice de busca a partir de `notes`/`transcript_segments`
  /// (recuperação de inconsistências e migração).
  Future<void> rebuildSearchIndex() async {
    await transaction(() async {
      await customStatement('DELETE FROM notes_fts');
      await customStatement(_rebuildIndexSql);
    });
  }

  /// Transforma o texto do usuário numa expressão MATCH de FTS5 segura:
  /// cada termo vira um prefixo entre aspas (AND implícito). Retorna `null`
  /// quando não há termo pesquisável.
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

  /// Busca FTS com ranking bm25 (título pesa mais) e trecho destacado.
  /// Pinned primeiro, depois por relevância. O trecho usa o corpo quando há
  /// match nele; senão, cai para o título destacado.
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
