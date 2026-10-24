import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/notifications/notifier.dart';

/// Uma tarefa com prazo, para o agendamento de lembretes.
class TaskReminder {
  const TaskReminder({
    required this.id,
    required this.noteId,
    required this.text,
    required this.due,
    required this.done,
    this.locked = false,
  });

  final String id;
  final String noteId;
  final String text;
  final DateTime? due;
  final bool done;

  /// A nota da tarefa está bloqueada: o lembrete não revela o texto (M7).
  final bool locked;
}

/// Corpo genérico dos lembretes de tarefa de notas bloqueadas (M7): nunca
/// expõe o texto nem o título da tarefa.
const _lockedTaskBody = 'Você tem uma tarefa com prazo hoje';

/// Agenda e cancela as notificações da Fase 3, respeitando os toggles e os
/// horários configuráveis (Geral). A lógica de datas é determinística e
/// testável via [FakeNotifier].
class NotificationScheduler {
  NotificationScheduler({
    required Notifier notifier,
    required SettingsStore settings,
  }) : _notifier = notifier,
       _settings = settings;

  final Notifier _notifier;
  final SettingsStore _settings;

  /// Keys das tarefas com lembrete ativo, persistidas para cancelar lembretes
  /// de tarefas removidas entre sessões (reagendamento no boot).
  Set<String> get _knownTaskKeys => _settings.scheduledTaskKeys.toSet();

  // ---------------- Nota pronta ----------------

  /// Mostra "Nota pronta: `<título>`" (ou o erro) quando a janela está fora de
  /// foco. Chamado ao fim do pipeline.
  Future<void> notifyNoteReady({
    required String noteId,
    required String title,
    required bool windowFocused,
    bool failed = false,
  }) async {
    if (!_settings.noteReadyNotif || windowFocused) return;
    await _notifier.show(
      id: 'note-ready:$noteId',
      title: failed ? 'Não foi possível processar a nota' : 'Nota pronta',
      body: failed
          ? 'Tente transcrever ou resumir de novo.'
          : (title.isEmpty ? 'Sua nota de voz está pronta.' : title),
      payload: AppNotification(
        kind: NotificationKind.noteReady,
        noteId: noteId,
      ),
    );
  }

  // ---------------- Tarefas com prazo ----------------

  /// (Re)agenda os lembretes de todas as [tasks] com prazo e cancela os de
  /// tarefas concluídas ou removidas. Idempotente (chamável no boot e após o
  /// sync).
  Future<void> syncTaskReminders(
    List<TaskReminder> tasks, {
    DateTime? now,
  }) async {
    final nowAt = now ?? DateTime.now();
    final hour = _settings.taskReminderHour;
    final eve = _settings.taskEveReminder;
    final enabled = _settings.remindTasks;

    final desired = <String>{};
    if (enabled) {
      for (final t in tasks) {
        final due = t.due;
        if (t.done || due == null) continue;
        final at = _atHour(due, hour);
        if (at.isAfter(nowAt)) {
          final key = 'task:${t.id}';
          desired.add(key);
          await _notifier.schedule(
            id: key,
            when: at,
            title: 'Tarefa com prazo hoje',
            body: t.locked ? _lockedTaskBody : t.text,
            payload: AppNotification(
              kind: NotificationKind.taskDue,
              noteId: t.noteId,
            ),
          );
        }
        if (eve) {
          final eveAt = _atHour(due.subtract(const Duration(days: 1)), hour);
          if (eveAt.isAfter(nowAt)) {
            final key = 'task-eve:${t.id}';
            desired.add(key);
            await _notifier.schedule(
              id: key,
              when: eveAt,
              title: 'Tarefa com prazo amanhã',
              body: t.locked ? _lockedTaskBody : t.text,
              payload: AppNotification(
                kind: NotificationKind.taskDue,
                noteId: t.noteId,
              ),
            );
          }
        }
      }
    }

    // Cancela os lembretes que não são mais desejados (concluídos/removidos/
    // toggle desligado).
    for (final key in _knownTaskKeys.difference(desired)) {
      await _notifier.cancel(key);
    }
    await _settings.setScheduledTaskKeys(desired.toList());
  }

  // ---------------- Pergunta do diário ----------------

  /// Agenda a pergunta do diário para o próximo horário configurado (padrão
  /// 21h), com o texto de [prompt] (o `dailyPrompt` do dia seguinte).
  Future<void> scheduleDiaryPrompt({
    required String prompt,
    DateTime? now,
  }) async {
    if (!_settings.diaryPromptNotif) {
      await _notifier.cancel('diary-prompt');
      return;
    }
    final at = _nextOccurrence(
      now ?? DateTime.now(),
      _settings.diaryPromptHour,
    );
    await _notifier.schedule(
      id: 'diary-prompt',
      when: at,
      title: 'Pergunta do diário',
      body: prompt,
      payload: AppNotification(
        kind: NotificationKind.diaryPrompt,
        date: _ymd(at),
      ),
    );
  }

  // ---------------- Resumo semanal ----------------

  /// Agenda o resumo semanal para a próxima segunda no horário configurado.
  Future<void> scheduleWeeklySummary({DateTime? now}) async {
    if (!_settings.weeklySummary) {
      await _notifier.cancel('weekly-summary');
      return;
    }
    final at = nextMonday(now ?? DateTime.now(), _settings.weeklySummaryHour);
    await _notifier.schedule(
      id: 'weekly-summary',
      when: at,
      title: 'Resumo da semana',
      body: 'Seu panorama da semana está pronto.',
      payload: AppNotification(
        kind: NotificationKind.weeklySummary,
        date: _ymd(weekStartOf(at)),
      ),
    );
  }

  /// True se o resumo semanal já deveria ter rodado (segunda no horário) e não
  /// rodou — para gerar na primeira abertura depois do Mac desligado.
  bool shouldGenerateWeeklyNow(DateTime now) {
    if (!_settings.weeklySummary) return false;
    final last = _settings.lastWeeklySummaryAt;
    final thisWeekMonday = nextMonday(
      now.subtract(const Duration(days: 7)),
      _settings.weeklySummaryHour,
    );
    if (now.isBefore(thisWeekMonday)) return false;
    return last == null || last.isBefore(thisWeekMonday);
  }

  // ---------------- date helpers (puras) ----------------

  /// [date] no [hour] do mesmo dia (minutos/segundos zerados).
  static DateTime _atHour(DateTime date, int hour) =>
      DateTime(date.year, date.month, date.day, hour);

  /// Próxima ocorrência do [hour] a partir de [now] (hoje se ainda não passou,
  /// senão amanhã).
  static DateTime _nextOccurrence(DateTime now, int hour) {
    final today = DateTime(now.year, now.month, now.day, hour);
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  /// Próxima segunda-feira no [hour] (hoje se for segunda e ainda não passou).
  static DateTime nextMonday(DateTime now, int hour) {
    var day = DateTime(now.year, now.month, now.day, hour);
    if (day.weekday == DateTime.monday && day.isAfter(now)) return day;
    do {
      day = day.add(const Duration(days: 1));
    } while (day.weekday != DateTime.monday);
    return day;
  }

  /// A segunda-feira da semana de [date] (início da semana).
  static DateTime weekStartOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
