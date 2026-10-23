import 'dart:async';
import 'dart:io';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';

/// Aplica as políticas de privacidade de dados do usuário:
///
/// * **Retenção** ("Para sempre", "1 ano", "90 dias", "30 dias"): apaga notas
///   (e seus arquivos de áudio) mais antigas que o limite.
/// * **Apagar áudio após transcrever**: remove os arquivos de áudio das notas
///   já prontas, preservando a transcrição e o resumo.
///
/// Roda uma varredura no boot e, enquanto o app estiver aberto, a cada 24h.
class RetentionService {
  RetentionService({
    required SettingsStore settings,
    required NoteRepository notes,
    AudioUploadQueue? audioQueue,
  }) : _settings = settings,
       _notes = notes,
       _audioQueue = audioQueue;

  final SettingsStore _settings;
  final NoteRepository _notes;

  /// Opcional (só com backend): quando o sync está ligado, o áudio precisa
  /// subir antes de ser apagado, então a remoção é delegada à fila.
  final AudioUploadQueue? _audioQueue;

  Timer? _timer;

  /// Converte o rótulo de retenção em dias, ou `null` para "Para sempre".
  static int? retentionDays(String label) => switch (label) {
    '30 dias' => 30,
    '90 dias' => 90,
    '1 ano' => 365,
    _ => null, // "Para sempre" (ou valor desconhecido): nunca expira.
  };

  /// Inicia a varredura no boot e agenda uma diária. Idempotente.
  void start() {
    unawaited(sweep());
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(hours: 24),
      (_) => unawaited(sweep()),
    );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// Executa as duas políticas para o instante [now] (default: agora).
  Future<void> sweep({DateTime? now}) async {
    final at = now ?? DateTime.now();
    try {
      await _applyRetention(at);
      await _applyDeleteAudioAfter();
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'retention_sweep',
        category: 'privacy',
      );
    }
  }

  Future<void> _applyRetention(DateTime now) async {
    final days = retentionDays(_settings.retention);
    if (days == null) return;
    final cutoff = now.subtract(Duration(days: days));
    final all = await _notes.getAllNotes();
    for (final note in all) {
      if (note.createdAt.isBefore(cutoff)) {
        await _deleteFiles(note);
        await _notes.deleteNote(note.id);
      }
    }
  }

  Future<void> _applyDeleteAudioAfter() async {
    if (!_settings.deleteAudioAfter) return;
    final all = await _notes.getAllNotes();
    for (final note in all) {
      if (note.status != NoteStatus.ready) continue;
      final hasAudio =
          note.playbackPath != null ||
          note.micWavPath != null ||
          note.systemWavPath != null;
      if (!hasAudio) continue;

      // Sync ligado + há `.m4a`: sobe antes de apagar. Enfileira (idempotente)
      // e deixa a fila remover o arquivo local após o upload concluir, para não
      // perder o áudio que ainda não está no servidor.
      final playback = note.playbackPath;
      if (_settings.syncEnabled && _audioQueue != null && playback != null) {
        await _audioQueue.enqueue(note.id, playback);
        continue;
      }

      // Sync desligado (ou sem áudio para subir): apaga imediatamente.
      await _deleteFiles(note);
      await _notes.clearAudioPaths(note.id);
    }
  }

  Future<void> _deleteFiles(NoteRow note) async {
    for (final path in [
      note.playbackPath,
      note.micWavPath,
      note.systemWavPath,
    ]) {
      if (path == null) continue;
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } on Object catch (e, st) {
        await AppLogger.error(
          e,
          st,
          reason: 'retention_delete_file',
          category: 'privacy',
        );
      }
    }
  }
}
