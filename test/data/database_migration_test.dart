import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

import '../helpers/test_db.dart';

/// Recria o estado do índice FTS do schema v1 (coluna `note_id UNINDEXED` +
/// gatilhos por segmento) para validar a migração.
const _v1Fts = '''
CREATE VIRTUAL TABLE notes_fts USING fts5(
  note_id UNINDEXED, title, body,
  tokenize = 'unicode61 remove_diacritics 2'
)''';

const _v1Triggers = <String>[
  '''
CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(note_id, title, body) VALUES (new.id, new.title, '');
END''',
  '''
CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
  DELETE FROM notes_fts WHERE note_id = old.id;
END''',
  '''
CREATE TRIGGER notes_au AFTER UPDATE OF title ON notes BEGIN
  UPDATE notes_fts SET title = new.title WHERE note_id = new.id;
END''',
  '''
CREATE TRIGGER seg_ai AFTER INSERT ON transcript_segments BEGIN
  UPDATE notes_fts SET body = (
    SELECT COALESCE(group_concat(content, ' '), '')
    FROM transcript_segments WHERE note_id = new.note_id
  ) WHERE note_id = new.note_id;
END''',
];

/// Esquema v2 mínimo da tabela `notes` (sem as colunas do v3), para validar a
/// migração v2 → v3 (novas colunas + tabelas + seed).
const _v2Notes = '''
CREATE TABLE notes (
  id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  playback_path TEXT,
  mic_wav_path TEXT,
  system_wav_path TEXT,
  status TEXT NOT NULL,
  pinned INTEGER NOT NULL DEFAULT 0,
  source TEXT NOT NULL
)''';

const _v2Segments = '''
CREATE TABLE transcript_segments (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  note_id TEXT NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
  speaker TEXT NOT NULL,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  content TEXT NOT NULL
)''';

void main() {
  late Directory tmp;
  late File file;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rbnotes_mig');
    file = File(p.join(tmp.path, 'rbnotes.sqlite'));
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'upgrade v1 → v3 recria o FTS, preserva a busca e semeia pastas',
    () async {
      final setup = AppDatabase.forTesting(NativeDatabase(file));
      await seedNote(setup, id: 'a', title: 'Reunião de planejamento');
      await seedSegment(
        setup,
        noteId: 'a',
        content: 'vamos revisar o orçamento trimestral',
      );

      // Rebaixa o índice/gatilhos para o formato v1 e marca user_version = 1.
      for (final name in ['notes_ai', 'notes_ad', 'notes_au']) {
        await setup.customStatement('DROP TRIGGER IF EXISTS $name');
      }
      await setup.customStatement('DROP TABLE IF EXISTS notes_fts');
      await setup.customStatement(_v1Fts);
      for (final sql in _v1Triggers) {
        await setup.customStatement(sql);
      }
      await setup.customStatement('PRAGMA user_version = 1');
      await setup.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      final repo = NoteRepository(migrated);

      expect((await repo.search('planejamento')).single.note.id, 'a');
      expect((await repo.search('orçamento')).single.note.id, 'a');
      // v3 semeia as pastas do design.
      final folders = await migrated.select(migrated.folders).get();
      expect(folders.map((f) => f.id), containsAll(['trabalho', 'diario']));

      await migrated.close();
    },
  );

  test('upgrade v2 → v3 adiciona colunas/tabelas e preserva a nota', () async {
    // Monta um esquema v2 cru (sem as colunas/tabelas do v3).
    final raw = NativeDatabase(file);
    final v2 = AppDatabase.forTesting(raw);
    // Zera o esquema v3 criado pelo onCreate e instala o v2 manualmente.
    await v2.customStatement('DROP TABLE IF EXISTS transcript_segments');
    await v2.customStatement('DROP TABLE IF EXISTS notes');
    await v2.customStatement('DROP TABLE IF EXISTS notes_fts');
    await v2.customStatement('DROP TABLE IF EXISTS folders');
    await v2.customStatement('DROP TABLE IF EXISTS note_ai');
    await v2.customStatement(_v2Notes);
    await v2.customStatement(_v2Segments);
    await v2.customStatement(
      "INSERT INTO notes (id, title, created_at, updated_at, status, source) "
      "VALUES ('n', 'Nota antiga', 0, 0, 'ready', 'recording')",
    );
    await v2.customStatement('PRAGMA user_version = 2');
    await v2.close();

    final migrated = AppDatabase.forTesting(NativeDatabase(file));

    // As novas colunas existem e têm os defaults.
    final note = await (migrated.select(
      migrated.notes,
    )..where((n) => n.id.equals('n'))).getSingle();
    expect(note.title, 'Nota antiga');
    expect(note.kind, NoteKind.note);
    expect(note.aiStatus, AiStatus.none);
    expect(note.favorite, isFalse);
    expect(note.folderId, isNull);

    // As novas tabelas existem e as pastas foram semeadas.
    final folders = await migrated.select(migrated.folders).get();
    expect(folders.length, 5);
    final prompts = await migrated.select(migrated.diaryPrompts).get();
    expect(prompts, isNotEmpty);

    await migrated.close();
  });
}
