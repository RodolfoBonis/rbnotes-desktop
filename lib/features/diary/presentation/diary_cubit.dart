import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/diary/domain/diary_calendar.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

class DiaryState extends Equatable {
  const DiaryState({
    this.promptIndex = 0,
    this.prompts = const [],
    this.calendar = const DiaryCalendar(cells: [], streak: 0),
    this.monthSummary = '',
    this.themes = const [],
    this.entriesCount = 0,
    this.loading = true,
    this.monthLoaded = false,
  });

  final int promptIndex;
  final List<DiaryPromptRow> prompts;
  final DiaryCalendar calendar;
  final String monthSummary;
  final List<DiaryTheme> themes;
  final int entriesCount;
  final bool loading;

  /// O resumo do mês já foi carregado (só roda após o app estar desbloqueado,
  /// para o diaryMonth nunca sair com o app travado).
  final bool monthLoaded;

  String get prompt =>
      prompts.isEmpty ? '' : prompts[promptIndex % prompts.length].question;

  DiaryState copyWith({
    int? promptIndex,
    List<DiaryPromptRow>? prompts,
    DiaryCalendar? calendar,
    String? monthSummary,
    List<DiaryTheme>? themes,
    int? entriesCount,
    bool? loading,
    bool? monthLoaded,
  }) => DiaryState(
    promptIndex: promptIndex ?? this.promptIndex,
    prompts: prompts ?? this.prompts,
    calendar: calendar ?? this.calendar,
    monthSummary: monthSummary ?? this.monthSummary,
    themes: themes ?? this.themes,
    entriesCount: entriesCount ?? this.entriesCount,
    loading: loading ?? this.loading,
    monthLoaded: monthLoaded ?? this.monthLoaded,
  );

  @override
  List<Object?> get props => [
    promptIndex,
    prompts,
    calendar,
    monthSummary,
    themes,
    entriesCount,
    loading,
    monthLoaded,
  ];
}

/// Estado do Diário: pergunta do dia, calendário/sequência, resumo do mês e
/// bloqueio por Touch ID.
class DiaryCubit extends Cubit<DiaryState> {
  DiaryCubit({
    required DiaryRepository diary,
    required NoteRepository notes,
    required NoteAiRepository noteAi,
    required AiClient ai,
  }) : _diary = diary,
       _notes = notes,
       _noteAi = noteAi,
       _ai = ai,
       super(const DiaryState());

  final DiaryRepository _diary;
  final NoteRepository _notes;
  final NoteAiRepository _noteAi;
  final AiClient _ai;

  Future<void> load() async {
    final now = DateTime.now();
    final prompts = await _diary.getPrompts();
    final days = await _diary.entryDaysInMonth(now);
    final calendar = buildDiaryCalendar(
      reference: now,
      entryDays: days,
      now: now,
    );
    emit(
      state.copyWith(
        prompts: prompts,
        calendar: calendar,
        entriesCount: days.length,
        loading: false,
      ),
    );
  }

  /// Carrega o resumo do mês (diaryMonth). Só deve ser chamado com o app
  /// desbloqueado; é idempotente (não repete se já carregou).
  Future<void> loadMonth() async {
    if (state.monthLoaded) return;
    emit(state.copyWith(monthLoaded: true));
    await _loadMonth(DateTime.now());
  }

  Future<void> _loadMonth(DateTime now) async {
    try {
      final diaryNotes = (await _notes.getAllNotes())
          .where((n) => n.kind == NoteKind.diary)
          .toList();
      final entries = <String>[];
      for (final n in diaryNotes) {
        final ai = await _noteAi.getNoteAi(n.id);
        entries.add(ai?.tldr ?? n.title);
      }
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final result = await _ai.diaryMonth(month: month, entries: entries);
      emit(
        state.copyWith(monthSummary: result.summary, themes: result.themes),
      );
    } on Object catch (e, st) {
      await AppLogger.error(e, st, reason: 'diary_month', category: 'ai');
    }
  }

  void nextPrompt() => emit(state.copyWith(promptIndex: state.promptIndex + 1));
}
