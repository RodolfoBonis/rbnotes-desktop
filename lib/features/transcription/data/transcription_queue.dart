import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/transcription/domain/transcription_logic.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Progresso de transcrição de uma nota (0..1), ou estado terminal.
///
/// Estados terminais são mutuamente exclusivos: [done] (sucesso, possivelmente
/// [partial] quando o áudio do sistema falhou mas o mic foi salvo), [failed]
/// (erro reportado) ou [cancelled] (transcrição cancelada — não é erro).
class TranscriptionProgress extends Equatable {
  const TranscriptionProgress({
    required this.noteId,
    required this.progress,
    this.done = false,
    this.failed = false,
    this.cancelled = false,
    this.partial = false,
  });

  final String noteId;
  final double progress;
  final bool done;
  final bool failed;
  final bool cancelled;
  final bool partial;

  /// Chegou ao fim (sucesso, falha ou cancelamento) — sai da UI de progresso.
  bool get isTerminal => done || failed || cancelled;

  @override
  List<Object?> get props => [
    noteId,
    progress,
    done,
    failed,
    cancelled,
    partial,
  ];
}

/// Fila serial de transcrição em background.
///
/// Transcreve `mic.wav` (eu) e, quando existe, `system.wav` (outros), junta os
/// segmentos por tempo, salva e gera o título automático. Emite progresso por
/// nota em [progress]; a lista de notas assina para mostrar a barra.
///
/// É robusta por construção: nenhuma falha de uma nota derruba o processamento
/// das demais, e cancelamento/exclusão são tratados sem reportar erro.
class TranscriptionQueue {
  TranscriptionQueue({
    required RbNative native,
    required NoteRepository repository,
    required SettingsStore settings,
    required VocabularyRepository vocabulary,
    bool Function(String path)? fileExists,
  }) : _native = native,
       _repository = repository,
       _settings = settings,
       _vocabulary = vocabulary,
       _fileExists = fileExists ?? _defaultFileExists;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  final RbNative _native;
  final NoteRepository _repository;
  final SettingsStore _settings;
  final VocabularyRepository _vocabulary;

  /// Checagem de existência de arquivo (injetável para teste).
  final bool Function(String path) _fileExists;

  /// Chave em [SharedPreferences] com os ids já reenfileirados pela recuperação
  /// pós-migração (bug 2) — para nunca reprocessar a mesma nota em loop.
  static const recoveredFailedKey = 'transcription.recovered_failed';

  final _queue = Queue<String>();
  final _controller = StreamController<TranscriptionProgress>.broadcast();
  bool _processing = false;

  /// Nota sendo processada agora (para dedup contra a fila).
  String? _current;

  Stream<TranscriptionProgress> get progress => _controller.stream;

  /// Enfileira uma nota para transcrição (ignora duplicatas pendentes ou a nota
  /// que já está em processamento).
  void enqueue(String noteId) {
    if (_queue.contains(noteId) || _current == noteId) return;
    _queue.add(noteId);
    unawaited(_drain());
  }

  /// Reenfileira uma nota (ex.: botão "Tentar de novo" após falha).
  void retry(String noteId) => enqueue(noteId);

  /// No boot, reenfileira todas as notas presas em `transcribing` (o app pode
  /// ter sido encerrado no meio da transcrição).
  Future<void> requeueInterrupted() async {
    try {
      final pending = await _repository.notesWithStatus(
        NoteStatus.transcribing,
      );
      for (final note in pending) {
        enqueue(note.id);
      }
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'requeue_interrupted',
        category: 'transcription',
      );
    }
  }

  /// No boot (depois da migração de schema), reenfileira **uma única vez** cada
  /// nota `failed` que ainda tem `mic_wav_path` existente em disco e 0
  /// segmentos — exatamente as vítimas do bug de migração que fazia
  /// `replaceSegments` falhar. Marca cada id em [prefs] para nunca entrar em
  /// loop, mesmo que volte a falhar.
  Future<void> recoverFailedNotes(SharedPreferences prefs) async {
    try {
      final already =
          prefs.getStringList(recoveredFailedKey)?.toSet() ?? <String>{};
      final failed = await _repository.notesWithStatus(NoteStatus.failed);
      var changed = false;
      for (final note in failed) {
        if (already.contains(note.id)) continue;
        final mic = note.micWavPath;
        if (mic == null || !_fileExists(mic)) continue;
        final segments = await _repository.getSegments(note.id);
        if (segments.isNotEmpty) continue;
        already.add(note.id);
        changed = true;
        enqueue(note.id);
      }
      if (changed) {
        await prefs.setStringList(recoveredFailedKey, already.toList());
        AppLogger.info(
          'recovered failed notes after migration',
          category: 'transcription',
          data: {'count': already.length},
        );
      }
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'recover_failed_notes',
        category: 'transcription',
      );
    }
  }

  /// Cancela a transcrição dos `.wav` de [note] e a remove da fila. Deve ser
  /// chamado ANTES de apagar os arquivos da nota.
  Future<void> cancel(NoteRow note) async {
    _queue.remove(note.id);
    for (final path in [note.micWavPath, note.systemWavPath]) {
      if (path == null) continue;
      try {
        await _native.cancelTranscription(path);
      } on Object catch (e, st) {
        await AppLogger.error(
          e,
          st,
          reason: 'cancel_transcription',
          category: 'transcription',
        );
      }
    }
  }

  /// Loop de drenagem protegido: processa a fila inteira e nunca morre por uma
  /// exceção não prevista (cada item é isolado).
  Future<void> _drain() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final noteId = _queue.removeFirst();
        try {
          await _process(noteId);
        } on Object catch (e, st) {
          // Rede de segurança: _process já trata tudo, mas se algo escapar o
          // loop continua com as próximas notas.
          await AppLogger.error(
            e,
            st,
            reason: 'drain',
            category: 'transcription',
          );
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _process(String noteId) async {
    _current = noteId;
    try {
      final note = await _repository.getNote(noteId);
      // Nota apagada durante o processamento (ou antes): sem erro.
      if (note == null) return;

      final micPath = note.micWavPath;
      if (micPath == null) {
        await _repository.setStatus(noteId, NoteStatus.failed);
        _controller.add(
          TranscriptionProgress(noteId: noteId, progress: 0, failed: true),
        );
        return;
      }

      await _repository.setStatus(noteId, NoteStatus.transcribing);
      _emit(noteId, 0);

      final model = _settings.model;
      final initialPrompt = await _vocabulary.initialPrompt();
      final systemPath = note.systemWavPath;
      final hasSystem = systemPath != null;

      final mic = await _native.transcribe(
        wavPath: micPath,
        model: model,
        language: _settings.languageCode,
        initialPrompt: initialPrompt,
        onProgress: (p) => _emit(noteId, hasSystem ? p * 0.5 : p),
      );

      var partial = false;
      var system = const <TranscriptSegment>[];
      if (hasSystem) {
        try {
          system = await _native.transcribe(
            wavPath: systemPath,
            model: model,
            language: _settings.languageCode,
            initialPrompt: initialPrompt,
            onProgress: (p) => _emit(noteId, 0.5 + p * 0.5),
          );
        } on RbNativeException catch (e, st) {
          // Cancelamento propaga para o tratamento terminal; qualquer outra
          // falha do sistema é parcial: salvamos o mic e seguimos.
          if (e.code == RbNativeErrorCode.transcriptionCancelled) rethrow;
          partial = true;
          AppLogger.warning(
            'system audio transcription failed; saving mic only',
            category: 'transcription',
            error: e,
          );
          await AppLogger.error(
            e,
            st,
            reason: 'transcribe_system_partial',
            category: 'transcription',
          );
        }
      }

      final merged = mergeSpeakerSegments(mic: mic, system: system);
      await _repository.replaceSegments(noteId, merged);

      if (note.title.trim().isEmpty) {
        final title = titleFromSegments(merged);
        // Título provisório (primeiras palavras): marcado como automático
        // para o título gerado pelo Claude poder substituí-lo depois.
        if (title.isNotEmpty) {
          await _repository.updateTitle(noteId, title, autoTitle: true);
        }
      }
      await _repository.setStatus(noteId, NoteStatus.ready);
      _controller.add(
        TranscriptionProgress(
          noteId: noteId,
          progress: 1,
          done: true,
          partial: partial,
        ),
      );
    } on RbNativeException catch (e, st) {
      if (e.code == RbNativeErrorCode.transcriptionCancelled) {
        // Cancelamento não é erro: sem Sentry, estado terminal distinto.
        AppLogger.info('transcription cancelled', category: 'transcription');
        _controller.add(
          TranscriptionProgress(noteId: noteId, progress: 0, cancelled: true),
        );
        return;
      }
      await AppLogger.error(
        e,
        st,
        reason: 'transcribe',
        category: 'transcription',
      );
      await _failQuietly(noteId);
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'transcribe',
        category: 'transcription',
      );
      await _failQuietly(noteId);
    } finally {
      _current = null;
    }
  }

  /// Marca a nota como `failed` sem deixar escapar erro (a nota pode ter sido
  /// apagada nesse meio-tempo).
  Future<void> _failQuietly(String noteId) async {
    try {
      await _repository.setStatus(noteId, NoteStatus.failed);
    } on Object catch (_) {
      // nota provavelmente apagada; ignore.
    }
    _controller.add(
      TranscriptionProgress(noteId: noteId, progress: 0, failed: true),
    );
  }

  void _emit(String noteId, double progress) {
    _controller.add(
      TranscriptionProgress(noteId: noteId, progress: progress.clamp(0, 1)),
    );
  }

  Future<void> dispose() => _controller.close();
}
