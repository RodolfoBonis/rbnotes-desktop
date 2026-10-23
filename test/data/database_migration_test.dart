import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

import '../helpers/test_db.dart';

/// Recria o estado do índice FTS do schema v1 (coluna `note_id UNINDEXED` +
/// gatilhos por segmento) para validar a migração para v2.
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
  '''
CREATE TRIGGER seg_au AFTER UPDATE ON transcript_segments BEGIN
  UPDATE notes_fts SET body = (
    SELECT COALESCE(group_concat(content, ' '), '')
    FROM transcript_segments WHERE note_id = new.note_id
  ) WHERE note_id = new.note_id;
END''',
  '''
CREATE TRIGGER seg_ad AFTER DELETE ON transcript_segments BEGIN
  UPDATE notes_fts SET body = (
    SELECT COALESCE(group_concat(content, ' '), '')
    FROM transcript_segments WHERE note_id = old.note_id
  ) WHERE note_id = old.note_id;
END''',
];

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

  test('upgrade de schema v1 → v2 recria o FTS e preserva a busca', () async {
    // 1) Cria a base (schema v2), insere dados e então rebaixa o índice para o
    //    formato v1, marcando user_version = 1.
    final setup = AppDatabase.forTesting(NativeDatabase(file));
    await seedNote(setup, id: 'a', title: 'Reunião de planejamento');
    await seedSegment(
      setup,
      noteId: 'a',
      content: 'vamos revisar o orçamento trimestral',
    );

    // Derruba o índice/gatilhos v2 e instala os v1.
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

    // 2) Reabre: drift detecta user_version 1 < 2 e roda a migração.
    final migrated = AppDatabase.forTesting(NativeDatabase(file));
    final repo = NoteRepository(migrated);

    // A busca funciona por título e por corpo (índice reconstruído do zero a
    // partir de notes/transcript_segments).
    expect((await repo.search('planejamento')).single.note.id, 'a');
    expect((await repo.search('orçamento')).single.note.id, 'a');

    await migrated.close();
  });
}
