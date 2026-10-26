import 'dart:async';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_exceptions.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/notifications/notification_scheduler.dart';
import 'package:rbnotes/notifications/notifier.dart';

/// Orquestra as 4 notificações: reagenda no boot e após o sync (tarefas com
/// prazo, pergunta do diário, resumo semanal) e roteia os toques.
///
/// O roteamento (abrir nota/diário/resumo) é delegado aos callbacks definidos
/// pela UI (`onOpenNote`/`onOpenDiary`/`onOpenWeekly`), porque só a camada de
/// apresentação conhece a navegação.
class NotificationCoordinator {
  NotificationCoordinator({
    required Notifier notifier,
    required NotificationScheduler scheduler,
    required NoteAiRepository noteAi,
    required NoteRepository notes,
    required AiClient ai,
    required SettingsStore settings,
    DateTime Function()? now,
  }) : _notifier = notifier,
       _scheduler = scheduler,
       _noteAi = noteAi,
       _notes = notes,
       _ai = ai,
       _settings = settings,
       _now = now ?? DateTime.now;

  final Notifier _notifier;
  final NotificationScheduler _scheduler;
  final NoteAiRepository _noteAi;
  final NoteRepository _notes;
  final AiClient _ai;
  final SettingsStore _settings;
  final DateTime Function() _now;

  StreamSubscription<AppNotification>? _tapSub;

  /// Roteamento (definido pela UI).
  void Function(String noteId)? onOpenNote;
  void Function()? onOpenDiary;
  void Function(DateTime weekStart)? onOpenWeekly;

  /// Toque na notificação "Gravar esta reunião?": inicia a gravação com áudio
  /// do sistema.
  void Function()? onStartMeeting;

  /// True se o resumo semanal deveria ter rodado (segunda já passou) e não
  /// rodou — a UI gera na primeira abertura.
  bool get weeklyDue => _scheduler.shouldGenerateWeeklyNow(_now());

  /// No boot: liga o roteamento dos toques e (re)agenda tudo.
  Future<void> start() async {
    _tapSub = _notifier.taps.listen(_onTap);
    await rescheduleAll();
  }

  /// Reagenda os três agendamentos (idempotente). Chamar no boot e após o sync.
  ///
  /// Nenhuma chamada de IA é feita aqui além da pergunta do diário, que é
  /// cacheada por data (ver [_rescheduleDiaryPrompt]). O resumo semanal só
  /// agenda a *notificação*; a IA (`weeklySummary`) roda na primeira abertura e
  /// é idempotente por semana via `SettingsStore.lastWeeklySummaryAt`.
  Future<void> rescheduleAll() async {
    await _rescheduleTasks();
    await _rescheduleDiaryPrompt();
    await _scheduler.scheduleWeeklySummary(now: _now());
  }

  Future<void> _rescheduleTasks() async {
    try {
      final actions = await _noteAi.allActions();
      // Notas bloqueadas: o lembrete não revela o texto da tarefa (M7).
      final lockedIds = (await _notes.getAllNotes())
          .where((n) => n.locked)
          .map((n) => n.id)
          .toSet();
      final tasks = [
        for (final a in actions)
          TaskReminder(
            id: a.id,
            noteId: a.noteId,
            text: a.content,
            due: a.due,
            done: a.done || a.dismissed,
            locked: lockedIds.contains(a.noteId),
          ),
      ];
      await _scheduler.syncTaskReminders(tasks, now: _now());
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'reschedule_tasks',
        category: 'notifications',
      );
    }
  }

  /// Reagenda a pergunta do diário **gerando-a no máximo uma vez por data**.
  ///
  /// Como `rescheduleAll()` roda a cada sync (a cada ~2 min), chamar a IA aqui
  /// sem cache criava 100+ jobs `daily_prompt` por dia e estourava a cota
  /// (bug de produção). A pergunta de cada data é persistida em
  /// [SettingsStore.cachedDiaryPrompt]; o sync só reagenda a partir do cache.
  /// Em erro (limite diário, rede) aplicamos backoff — até o próximo dia no
  /// limite diário, algumas horas nos demais — para não repetir a cada sync.
  Future<void> _rescheduleDiaryPrompt() async {
    if (!_settings.diaryPromptNotif) {
      await _scheduler.scheduleDiaryPrompt(prompt: '', now: _now());
      return;
    }

    final now = _now();
    final tomorrow = now.add(const Duration(days: 1));
    final ymd = _ymd(tomorrow);

    // 1. Cache: reagenda a partir do que já foi gerado para a data, sem IA.
    final cached = _settings.cachedDiaryPrompt(ymd);
    if (cached != null) {
      await _scheduler.scheduleDiaryPrompt(prompt: cached, now: now);
      return;
    }

    // 2. Backoff ativo após um erro recente: não tenta de novo a cada sync.
    final retryAt = _settings.diaryPromptRetryAt;
    if (retryAt != null && now.isBefore(retryAt)) return;

    // 3. Sem cache e fora do backoff: gera uma vez, persiste e reagenda.
    try {
      final prompt = await _ai.dailyPrompt(tomorrow);
      await _settings.setCachedDiaryPrompt(ymd, prompt);
      await _settings.clearDiaryPromptRetryAt();
      await _scheduler.scheduleDiaryPrompt(prompt: prompt, now: now);
    } on Object catch (e, st) {
      final backoffUntil = e is AiDailyLimitException
          ? _startOfNextDay(now)
          : now.add(const Duration(hours: 4));
      await _settings.setDiaryPromptRetryAt(backoffUntil);
      await AppLogger.error(
        e,
        st,
        reason: 'reschedule_diary_prompt',
        category: 'notifications',
      );
    }
  }

  static DateTime _startOfNextDay(DateTime now) =>
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void _onTap(AppNotification n) {
    switch (n.kind) {
      case NotificationKind.noteReady:
      case NotificationKind.taskDue:
        final id = n.noteId;
        if (id != null) onOpenNote?.call(id);
      case NotificationKind.diaryPrompt:
        onOpenDiary?.call();
      case NotificationKind.weeklySummary:
        final date = n.date;
        onOpenWeekly?.call(
          date != null
              ? DateTime.parse(date)
              : NotificationScheduler.weekStartOf(_now()),
        );
      case NotificationKind.meetingSuggestion:
        onStartMeeting?.call();
    }
  }

  Future<void> dispose() => _tapSub?.cancel() ?? Future.value();
}
