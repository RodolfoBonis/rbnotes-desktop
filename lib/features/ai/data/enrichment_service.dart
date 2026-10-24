import 'dart:async';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
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
  ///
  /// [force] (ação manual "Gerar resumo"/"Tentar de novo") ignora o auto-resumo
  /// desligado, mas continua respeitando a privacidade da pasta Pessoal.
  Future<void> enrichNote(String noteId, {bool force = false}) async {
    try {
      if (!force && !_settings.autoSummary) return;
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

      // Nunca persistir um resumo vazio/ inválido nem marcar `ready`: sem título
      // e tldr não há resumo (era o sintoma do bug do envelope SSE). Marca
      // `failed` com motivo — o usuário pode tentar de novo e o sync traz o
      // resumo bom do servidor no próximo pull.
      if (!_hasContent(ai)) {
        await AppLogger.error(
          StateError('enrich devolveu resumo vazio'),
          StackTrace.current,
          reason: 'enrich_empty',
          category: 'ai',
        );
        await _notes.setAiStatus(noteId, AiStatus.failed);
        return;
      }

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

  /// `true` se o resumo tem conteúdo mínimo (título e tldr). Um resumo sem eles
  /// nunca é legítimo — foi o que o bug do envelope gravava como `{}`.
  static bool _hasContent(NoteAi ai) =>
      ai.title.trim().isNotEmpty && ai.tldr.trim().isNotEmpty;

  /// No boot, re-enriquece as notas presas em `aiStatus = pending` de uma
  /// sessão anterior (o app pode ter fechado no meio) e **repara** as notas que
  /// o bug do envelope deixou com `note_ai` vazio marcado como `ready`. Garante
  /// que nunca haja um "Resumo em preparação…" sem um job real por trás (bug 6)
  /// nem um "ready" sem resumo de verdade.
  Future<void> requeuePending() async {
    try {
      await _repairEmptyReady();
      final pending = await _notes.notesWithAiStatus(AiStatus.pending);
      for (final note in pending) {
        unawaited(enrichNote(note.id, force: true));
      }
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'requeue_pending_enrich',
        category: 'ai',
      );
    }
  }

  /// Conserta as notas `ready` mas com `note_ai` vazio/ ausente (bug do
  /// envelope SSE): apaga o `note_ai` vazio local (para o `{}` não ir no push)
  /// e volta a nota para `pending`, que o loop acima re-enriquece.
  Future<void> _repairEmptyReady() async {
    final ready = await _notes.notesWithAiStatus(AiStatus.ready);
    for (final note in ready) {
      NoteAi? ai;
      try {
        ai = await _noteAi.getNoteAi(note.id);
      } on Object catch (_) {
        ai = null; // json corrompido conta como vazio.
      }
      if (ai != null && _hasContent(ai)) continue;
      await _noteAi.deleteLocal(note.id);
      await _notes.setAiStatus(note.id, AiStatus.pending);
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
