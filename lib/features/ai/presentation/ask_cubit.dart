import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

enum AskPhase { idle, thinking, streaming, done }

class AskState extends Equatable {
  const AskState({
    this.phase = AskPhase.idle,
    this.query = '',
    this.answer = '',
    this.sources = const [],
  });

  final AskPhase phase;
  final String query;
  final String answer;
  final List<AskSource> sources;

  AskState copyWith({
    AskPhase? phase,
    String? query,
    String? answer,
    List<AskSource>? sources,
  }) => AskState(
    phase: phase ?? this.phase,
    query: query ?? this.query,
    answer: answer ?? this.answer,
    sources: sources ?? this.sources,
  );

  @override
  List<Object?> get props => [phase, query, answer, sources];
}

/// "Perguntar às notas" (⌘K): monta candidatas e faz streaming da resposta.
class AskCubit extends Cubit<AskState> {
  AskCubit({
    required AiClient ai,
    required NoteRepository notes,
    required NoteAiRepository noteAi,
  }) : _ai = ai,
       _notes = notes,
       _noteAi = noteAi,
       super(const AskState());

  final AiClient _ai;
  final NoteRepository _notes;
  final NoteAiRepository _noteAi;
  StreamSubscription<AiDelta>? _sub;

  static const suggestions = [
    'O que ficou pendente esta semana?',
    'Resuma minhas reuniões de trabalho',
    'O que eu já pensei sobre o podcast?',
  ];

  void setQuery(String q) {
    emit(state.copyWith(query: q, phase: AskPhase.idle));
  }

  void reset() => emit(const AskState());

  Future<void> submit([String? preset]) async {
    final q = (preset ?? state.query).trim();
    if (q.isEmpty) return;
    emit(state.copyWith(query: q, phase: AskPhase.thinking, answer: ''));

    final candidates = await _candidates(q);
    await _sub?.cancel();
    _sub = _ai
        .ask(question: q, candidates: candidates)
        .listen(
          (delta) => emit(
            state.copyWith(
              phase: delta.isDone ? AskPhase.done : AskPhase.streaming,
              answer: delta.text,
              sources: delta.isDone ? delta.sources : state.sources,
            ),
          ),
          onError: (Object e, StackTrace st) {
            unawaited(AppLogger.error(e, st, reason: 'ask', category: 'ai'));
            emit(state.copyWith(phase: AskPhase.idle));
          },
        );
  }

  Future<List<AskCandidate>> _candidates(String query) async {
    // Busca por FTS; se vazia, usa todas as notas prontas.
    final hits = await _notes.search(query);
    final notes = hits.isNotEmpty
        ? hits.map((h) => h.note).toList()
        : (await _notes.getAllNotes())
              .where((n) => n.kind != NoteKind.diary)
              .take(6)
              .toList();
    final out = <AskCandidate>[];
    for (final n in notes.take(6)) {
      final ai = await _noteAi.getNoteAi(n.id);
      out.add(
        AskCandidate(
          noteId: n.id,
          title: n.title,
          tldr: ai?.tldr ?? '',
          transcript: ai?.tldr ?? '',
        ),
      );
    }
    return out;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
