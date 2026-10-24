import 'dart:async';

import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
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

  Future<void> _rescheduleDiaryPrompt() async {
    if (!_settings.diaryPromptNotif) {
      await _scheduler.scheduleDiaryPrompt(prompt: '', now: _now());
      return;
    }
    try {
      final tomorrow = _now().add(const Duration(days: 1));
      final prompt = await _ai.dailyPrompt(tomorrow);
      await _scheduler.scheduleDiaryPrompt(prompt: prompt, now: _now());
    } on Object catch (e, st) {
      await AppLogger.error(
        e,
        st,
        reason: 'reschedule_diary_prompt',
        category: 'notifications',
      );
    }
  }

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
