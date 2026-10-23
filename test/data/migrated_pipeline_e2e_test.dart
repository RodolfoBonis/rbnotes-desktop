import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DDL cru do MVP (v2): transcript_segments SEM words_json — o banco do dono.
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
  test(
    'pipeline completo sobre banco v2 migrado: transcreve, salva e enriquece '
    '(bug 1 morto de ponta a ponta)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final tmp = await Directory.systemTemp.createTemp('rbnotes_e2e');
      final dbFile = File(p.join(tmp.path, 'rbnotes.sqlite'));
      final micWav = File(p.join(tmp.path, 'n.mic.wav'))
        ..writeAsBytesSync(const [0, 0, 0, 0]);

      // 1) Monta o banco v2 cru e insere a nota do dono (em transcribing).
      final v2 = AppDatabase.forTesting(NativeDatabase(dbFile));
      await v2.customStatement('DROP TABLE IF EXISTS transcript_segments');
      await v2.customStatement('DROP TABLE IF EXISTS notes');
      await v2.customStatement('DROP TABLE IF EXISTS notes_fts');
      await v2.customStatement('DROP TABLE IF EXISTS folders');
      await v2.customStatement('DROP TABLE IF EXISTS note_ai');
      await v2.customStatement(_v2Notes);
      await v2.customStatement(_v2Segments);
      // Um banco v2 real tem notes_fts (formato v3). Criamos antes de inserir,
      // para o gatilho de INSERT indexar a nota.
      await v2.customStatement('''
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  title, body,
  tokenize = 'unicode61 remove_diacritics 2'
)''');
      await v2.customStatement('''
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, '');
END''');
      await v2.customStatement('''
CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  DELETE FROM notes_fts WHERE rowid = old.rowid;
END''');
      await v2.customStatement(
        'INSERT INTO notes '
        '(id, title, created_at, updated_at, status, source, mic_wav_path) '
        "VALUES ('n', '', 0, 0, 'transcribing', 'recording', '${micWav.path}')",
      );
      await v2.customStatement('PRAGMA user_version = 2');
      await v2.close();

      // 2) Reabre (migra para v4) e monta o pipeline real.
      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      final notes = NoteRepository(db);
      final noteAi = NoteAiRepository(db);
      final settings = SettingsStore(prefs);
      final queue = TranscriptionQueue(
        native: FakeRbNative(),
        repository: notes,
        settings: settings,
        vocabulary: VocabularyRepository(db),
      );
      final enrichment = EnrichmentService(
        ai: FakeAiClient(),
        notes: notes,
        noteAi: noteAi,
        vocabulary: VocabularyRepository(db),
        settings: settings,
      )..attachTo(queue);

      // 3) Roda a fila completa.
      queue.enqueue('n');
      await queue.progress.firstWhere((p) => p.done);

      // Espera o enrich (disparado no done) concluir — aiStatus = ready.
      var note = await notes.getNote('n');
      for (var i = 0; i < 100 && note!.aiStatus != AiStatus.ready; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        note = await notes.getNote('n');
      }

      // 4) Prova: segmentos salvos (replaceSegments funcionou pós-migração),
      // nota pronta e resumo gerado.
      expect(await notes.getSegments('n'), isNotEmpty);
      expect(note!.status, NoteStatus.ready);
      expect(note.aiStatus, AiStatus.ready);
      expect(await noteAi.getNoteAi('n'), isNotNull);

      await enrichment.dispose();
      await queue.dispose();
      await db.close();
      tmp.deleteSync(recursive: true);
    },
  );
}
