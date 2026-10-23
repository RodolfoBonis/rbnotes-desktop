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

const _createFtsTable = '''
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  note_id UNINDEXED, title, body,
  tokenize = 'unicode61 remove_diacritics 2'
)''';

const _ftsTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(note_id, title, body) VALUES (new.id, new.title, '');
END''',
  '''
CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  DELETE FROM notes_fts WHERE note_id = old.id;
END''',
  '''
CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE OF title ON notes BEGIN
  UPDATE notes_fts SET title = new.title WHERE note_id = new.id;
END''',
  '''
CREATE TRIGGER IF NOT EXISTS seg_ai AFTER INSERT ON transcript_segments BEGIN
  UPDATE notes_fts SET body = (
    SELECT COALESCE(group_concat(content, ' '), '')
    FROM transcript_segments WHERE note_id = new.note_id
  ) WHERE note_id = new.note_id;
END''',
  '''
CREATE TRIGGER IF NOT EXISTS seg_au AFTER UPDATE ON transcript_segments BEGIN
  UPDATE notes_fts SET body = (
    SELECT COALESCE(group_concat(content, ' '), '')
    FROM transcript_segments WHERE note_id = new.note_id
  ) WHERE note_id = new.note_id;
END''',
  '''
CREATE TRIGGER IF NOT EXISTS seg_ad AFTER DELETE ON transcript_segments BEGIN
  UPDATE notes_fts SET body = (
    SELECT COALESCE(group_concat(content, ' '), '')
    FROM transcript_segments WHERE note_id = old.note_id
  ) WHERE note_id = old.note_id;
END''',
];

const _searchSql = '''
SELECT n.*,
       bm25(notes_fts, 0.0, 10.0, 1.0) AS rank,
       snippet(notes_fts, 2, '[', ']', '…', 12) AS snippet
FROM notes_fts JOIN notes n ON n.id = notes_fts.note_id
WHERE notes_fts MATCH ?
ORDER BY n.pinned DESC, rank''';

@DriftDatabase(tables: [Notes, TranscriptSegments, Tags, NoteTags])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Para testes: injete um `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearchIndex();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
    // Migrações futuras entram aqui, versionadas por [schemaVersion].
    onUpgrade: (m, from, to) async {
      // schemaVersion 1 — ainda sem upgrades.
    },
  );

  /// Cria a tabela FTS5 (título + transcrição) e os gatilhos que a mantêm
  /// em sincronia com `notes` e `transcript_segments`.
  Future<void> _createSearchIndex() async {
    await customStatement(_createFtsTable);
    for (final sql in _ftsTriggers) {
      await customStatement(sql);
    }
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
  /// Pinned primeiro, depois por relevância.
  Future<List<NoteSearchHit>> search(String query) async {
    final match = buildMatchQuery(query);
    if (match == null) return [];
    final rows = await customSelect(
      _searchSql,
      variables: [Variable<String>(match)],
      readsFrom: {notes, transcriptSegments},
    ).get();
    return rows
        .map(
          (row) => NoteSearchHit(
            note: notes.map(row.data),
            snippet: row.read<String>('snippet'),
            rank: row.read<double>('rank'),
          ),
        )
        .toList();
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
