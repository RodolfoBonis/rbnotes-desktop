import 'dart:async';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/domain/privacy_masker.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:uuid/uuid.dart';

/// Após a transcrição, chama a IA (`enrich`) e salva resumo/insights/título/
/// falantes. Respeita as preferências de privacidade: a pasta Pessoal pode não
/// ser enviada, e CPF/telefone/cartão são mascarados antes do envio.
class EnrichmentService {
  EnrichmentService({
    required AiClient ai,
    required NoteRepository notes,
    required NoteAiRepository noteAi,
    required VocabularyRepository vocabulary,
    required SettingsStore settings,
    Uuid? uuid,
  }) : _ai = ai,
       _notes = notes,
       _noteAi = noteAi,
       _vocabulary = vocabulary,
       _settings = settings,
       _uuid = uuid ?? const Uuid();

  final AiClient _ai;
  final NoteRepository _notes;
  final NoteAiRepository _noteAi;
  final VocabularyRepository _vocabulary;
  final SettingsStore _settings;
  final Uuid _uuid;

  StreamSubscription<TranscriptionProgress>? _sub;

  /// Passa a enriquecer automaticamente cada nota que termina de transcrever.
  void attachTo(TranscriptionQueue queue) {
    _sub ??= queue.progress.listen((p) {
      if (p.done) unawaited(enrichNote(p.noteId));
    });
  }

  /// Enriquece uma nota: título, resumo, pontos, citação, ações, decisões,
  /// perguntas e nomes de falantes. Silencioso em caso de falha (marca
  /// `aiStatus = failed`, nunca derruba o app).
  Future<void> enrichNote(String noteId) async {
    try {
      if (!_settings.autoSummary) return;
      final note = await _notes.getNote(noteId);
      if (note == null) return;

      // Privacidade: pasta Pessoal pode ficar só com a transcrição local.
      if (_settings.skipPersonal && note.folderId == 'pessoal') {
        await _notes.setAiStatus(noteId, AiStatus.none);
        return;
      }

      final segments = await _notes.getSegments(noteId);
      if (segments.isEmpty) {
        await _notes.setAiStatus(noteId, AiStatus.none);
        return;
      }

      await _notes.setAiStatus(noteId, AiStatus.pending);
      final redact = _settings.redactSensitive;
      final hasOthers = segments.any((s) => s.speaker == SegmentSpeaker.others);
      final speakers = hasOthers ? const ['Você', 'Outros'] : const ['Você'];

      final aiSegments = [
        for (var i = 0; i < segments.length; i++)
          AiSegment(
            index: i,
            speaker: segments[i].speaker == SegmentSpeaker.me
                ? AiSpeaker.me
                : AiSpeaker.others,
            startMs: segments[i].startMs,
            endMs: segments[i].endMs,
            text: redact
                ? PrivacyMasker.mask(segments[i].content)
                : segments[i].content,
          ),
      ];

      final ai = await _ai.enrich(
        EnrichRequest(
          noteId: noteId,
          segments: aiSegments,
          speakers: speakers,
          folder: note.folderId,
          style: _settings.summaryStyle,
          length: _settings.summaryLength,
          extractTasks: _settings.extractTasks,
        ),
      );

      await _noteAi.saveNoteAi(noteId, ai);
      await _noteAi.replaceActions(noteId, ai.actions, genId: _uuid.v4);

      final resolvedSpeakers = <String>[
        'Você',
        ...ai.speakerNames.others,
      ];
      await _notes.setSpeakers(noteId, resolvedSpeakers.join('\u001f'));

      if (ai.title.trim().isNotEmpty &&
          (note.title.trim().isEmpty || note.autoTitle)) {
        await _notes.updateTitle(noteId, ai.title.trim(), autoTitle: true);
      }
      await _notes.setAiStatus(noteId, AiStatus.ready);
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'enrich', category: 'ai');
      try {
        await _notes.setAiStatus(noteId, AiStatus.failed);
      } on Object catch (_) {
        // nota apagada no meio-tempo; ignore.
      }
    }
  }

  /// Decodifica a lista de falantes persistida em `notes.speakersJson`.
  static List<String> decodeSpeakers(String? raw) {
    if (raw == null || raw.isEmpty) return const ['Você'];
    return raw.split('\u001f').where((s) => s.isNotEmpty).toList();
  }

  // Mantém o analyzer feliz sobre a dependência de vocabulário (usada pelo
  // pipeline de transcrição para o initialPrompt; exposta aqui p/ reuso).
  VocabularyRepository get vocabulary => _vocabulary;

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
