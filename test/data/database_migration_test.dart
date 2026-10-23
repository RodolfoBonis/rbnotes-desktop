import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';

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

/// Indice FTS saudavel (formato v3) + gatilhos, como num banco real do dono.
const _healthyFts = '''
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  title, body,
  tokenize = 'unicode61 remove_diacritics 2'
)''';

const _healthyFtsTriggers = <String>[
  '''
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, '');
END''',
  '''
CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  DELETE FROM notes_fts WHERE rowid = old.rowid;
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
      'INSERT INTO notes (id, title, created_at, updated_at, status, source) '
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

  test(
    'migracao conserta words_json e replaceSegments volta a funcionar '
    '(regressao do Resumo em preparacao infinito)',
    () async {
      // Monta o schema do MVP (v2): transcript_segments SEM words_json. Esse e
      // exatamente o banco do dono que travava em replaceSegments.
      final raw = NativeDatabase(file);
      final v2 = AppDatabase.forTesting(raw);
      await v2.customStatement('DROP TABLE IF EXISTS transcript_segments');
      await v2.customStatement('DROP TABLE IF EXISTS notes');
      await v2.customStatement('DROP TABLE IF EXISTS notes_fts');
      await v2.customStatement('DROP TABLE IF EXISTS folders');
      await v2.customStatement('DROP TABLE IF EXISTS note_ai');
      await v2.customStatement(_v2Notes);
      await v2.customStatement(_v2Segments);
      await v2.customStatement(
        'INSERT INTO notes (id, title, created_at, updated_at, status, source) '
        "VALUES ('n', 'Nota do MVP', 0, 0, 'transcribing', 'recording')",
      );
      await v2.customStatement(_healthyFts);
      for (final sql in _healthyFtsTriggers) {
        await v2.customStatement(sql);
      }
      await v2.customStatement(
        'INSERT INTO notes_fts(rowid, title, body) '
        "SELECT rowid, title, '' FROM notes",
      );
      await v2.customStatement('PRAGMA user_version = 2');
      await v2.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      final repo = NoteRepository(migrated);

      // A coluna que faltava passou a existir.
      final cols = await migrated
          .customSelect('PRAGMA table_info(transcript_segments)')
          .get();
      expect(
        cols.map((r) => r.read<String>('name')),
        contains('words_json'),
      );

      // E replaceSegments (que insere words_json) agora funciona de ponta a
      // ponta: antes da correcao isto lancava e a nota ia para failed.
      await repo.replaceSegments('n', const [
        DraftSegment(
          speaker: SegmentSpeaker.me,
          startMs: 0,
          endMs: 1500,
          content: 'primeiro segmento apos a migracao',
          wordsJson:
            '[{"text":"primeiro","startMs":0,"endMs":300,"prob":0.9}]',
        ),
      ]);

      final segments = await repo.getSegments('n');
      expect(segments, hasLength(1));
      expect(segments.single.content, 'primeiro segmento apos a migracao');
      expect(segments.single.wordsJson, isNotNull);
      // E a busca FTS foi recomposta pelo replaceSegments.
      expect((await repo.search('migracao')).single.note.id, 'n');

      await migrated.close();
    },
  );

  test(
    'reparo conserta um banco ja em v3 sem transcript_segments.words_json',
    () async {
      // Reproduz o estado exato do banco do dono: schema v3 completo, porem a
      // migracao v3 nunca adicionou words_json em transcript_segments.
      final raw = NativeDatabase(file);
      final db = AppDatabase.forTesting(raw);
      // Deixa o onCreate montar o v4 inteiro e entao removemos a coluna
      // recriando a tabela sem ela, e marcamos user_version = 3.
      await db.customStatement('DROP TABLE IF EXISTS transcript_segments');
      await db.customStatement(_v2Segments); // sem words_json
      await db.customStatement(
        'INSERT INTO notes (id, title, created_at, updated_at, status, source) '
        "VALUES ('n', 'Nota v3', 0, 0, 'transcribing', 'recording')",
      );
      // onCreate ja criou notes_fts e o gatilho de INSERT ja indexou a nota.
      await db.customStatement('PRAGMA user_version = 3');
      await db.close();

      final migrated = AppDatabase.forTesting(NativeDatabase(file));
      final repo = NoteRepository(migrated);

      final cols = await migrated
          .customSelect('PRAGMA table_info(transcript_segments)')
          .get();
      expect(cols.map((r) => r.read<String>('name')), contains('words_json'));

      await repo.replaceSegments('n', const [
        DraftSegment(
          speaker: SegmentSpeaker.me,
          startMs: 0,
          endMs: 1000,
          content: 'ok em v3',
          wordsJson: '[]',
        ),
      ]);
      expect(await repo.getSegments('n'), hasLength(1));

      await migrated.close();
    },
  );
}
