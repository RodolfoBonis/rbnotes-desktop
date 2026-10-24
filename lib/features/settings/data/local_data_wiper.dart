import 'dart:io';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';

/// Apaga todos os dados locais do RbNotes (banco, áudios, caches e estado de
/// sync). Reaproveitado pelo "Apagar dados locais" do logout e pela limpeza
/// final de "Apagar todos os dados".
///
/// Mantém o schema (as pastas/coleções embutidas voltam no próximo boot pelo
/// seeder). Nunca lança: cada passo tolera falha e segue, para o logout/erase
/// não travar por um arquivo preso.
class LocalDataWiper {
  LocalDataWiper({
    required AppDatabase db,
    required NoteRepository notes,
    required AppPaths paths,
    this.sync,
    this.audioQueue,
  }) : _db = db,
       _notes = notes,
       _paths = paths;

  final AppDatabase _db;
  final NoteRepository _notes;
  final AppPaths _paths;

  /// Opcionais (só com backend): reseta o cursor e esvazia a fila de upload.
  final SyncService? sync;
  final AudioUploadQueue? audioQueue;

  Future<void> wipe() async {
    await _deleteAudioFiles();
    _clearDir(_paths.recordingsDir);
    _clearDir(_paths.audioCacheDir);
    await _clearDatabase();
    await audioQueue?.clear();
    await sync?.resetCursor();
  }

  Future<void> _deleteAudioFiles() async {
    try {
      final notes = await _notes.getAllNotes();
      for (final note in notes) {
        for (final path in [
          note.playbackPath,
          note.micWavPath,
          note.systemWavPath,
        ]) {
          if (path == null) continue;
          try {
            final file = File(path);
            if (file.existsSync()) await file.delete();
          } on Object {
            // Arquivo ausente/preso: segue apagando o resto.
          }
        }
      }
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'wipe_audio', category: 'privacy');
    }
  }

  void _clearDir(String path) {
    try {
      final dir = Directory(path);
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync()) {
        try {
          entity.deleteSync(recursive: true);
        } on Object {
          // ignore
        }
      }
    } on Object {
      // ignore
    }
  }

  Future<void> _clearDatabase() async {
    try {
      await _db.transaction(() async {
        // Notes em cascata leva segmentos, note_ai, chat, actions e note_tags.
        await _db.delete(_db.notes).go();
        await _db.delete(_db.diaryEntries).go();
        await _db.delete(_db.vocabulary).go();
        await _db.delete(_db.tags).go();
        await _db.delete(_db.syncMeta).go();
      });
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'wipe_db', category: 'privacy');
    }
  }
}
