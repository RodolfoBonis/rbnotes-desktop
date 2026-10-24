import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/notifications/notification_scheduler.dart';
import 'package:rbnotes/notifications/notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsStore> settingsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsStore(await SharedPreferences.getInstance());
}

void main() {
  late FakeNotifier notifier;

  setUp(() => notifier = FakeNotifier());
  tearDown(() => notifier.dispose());

  group('nota pronta', () {
    test('mostra quando a janela está fora de foco', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      await s.notifyNoteReady(
        noteId: 'n1',
        title: 'Reunião de time',
        windowFocused: false,
      );
      expect(notifier.shown.single.body, 'Reunião de time');
      expect(notifier.shown.single.payload.noteId, 'n1');
    });

    test('não mostra com a janela em foco ou toggle desligado', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      await s.notifyNoteReady(noteId: 'n', title: 't', windowFocused: true);
      expect(notifier.shown, isEmpty);

      final off = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({'settings.notif.note_ready': false}),
      );
      await off.notifyNoteReady(noteId: 'n', title: 't', windowFocused: false);
      expect(notifier.shown, isEmpty);
    });

    test('mostra o texto de erro quando falhou', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      await s.notifyNoteReady(
        noteId: 'n',
        title: 't',
        windowFocused: false,
        failed: true,
      );
      expect(notifier.shown.single.title, contains('Não foi possível'));
    });
  });

  group('tarefas com prazo', () {
    test('agenda às 9h do dia do prazo', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      await s.syncTaskReminders(
        [
          TaskReminder(
            id: 't1',
            noteId: 'n1',
            text: 'Enviar proposta',
            due: DateTime(2026, 10, 30),
            done: false,
          ),
        ],
        now: DateTime(2026, 10, 24, 12),
      );
      final sch = notifier.scheduledFor('task:t1')!;
      expect(sch.when, DateTime(2026, 10, 30, 9));
      expect(sch.body, 'Enviar proposta');
    });

    // M7: lembrete de tarefa de nota bloqueada não vaza o texto.
    test('nota bloqueada usa corpo genérico e não revela o texto', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({'settings.notif.task_eve': true}),
      );
      await s.syncTaskReminders(
        [
          TaskReminder(
            id: 't1',
            noteId: 'n1',
            text: 'Ligar para o advogado sobre o processo',
            due: DateTime(2026, 10, 30),
            done: false,
            locked: true,
          ),
        ],
        now: DateTime(2026, 10, 24, 12),
      );
      final day = notifier.scheduledFor('task:t1')!;
      final eve = notifier.scheduledFor('task-eve:t1')!;
      expect(day.body, 'Você tem uma tarefa com prazo hoje');
      expect(eve.body, 'Você tem uma tarefa com prazo hoje');
      for (final n in notifier.scheduled) {
        expect(n.body.contains('advogado'), isFalse);
        expect(n.title.contains('advogado'), isFalse);
      }
    });

    test('ignora tarefas concluídas e prazos passados', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      await s.syncTaskReminders(
        [
          TaskReminder(
            id: 'done',
            noteId: 'n',
            text: 'x',
            due: DateTime(2026, 10, 30),
            done: true,
          ),
          TaskReminder(
            id: 'past',
            noteId: 'n',
            text: 'x',
            due: DateTime(2026, 10),
            done: false,
          ),
        ],
        now: DateTime(2026, 10, 24, 12),
      );
      expect(notifier.scheduled, isEmpty);
    });

    test('agenda a véspera quando ligado', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({'settings.notif.task_eve': true}),
      );
      await s.syncTaskReminders(
        [
          TaskReminder(
            id: 't1',
            noteId: 'n',
            text: 'x',
            due: DateTime(2026, 10, 30),
            done: false,
          ),
        ],
        now: DateTime(2026, 10, 24, 12),
      );
      expect(
        notifier.scheduledFor('task-eve:t1')!.when,
        DateTime(2026, 10, 29, 9),
      );
    });

    test('cancela lembretes de tarefas concluídas ou removidas', () async {
      final settings = await settingsWith({});
      final s = NotificationScheduler(notifier: notifier, settings: settings);
      final task = TaskReminder(
        id: 't1',
        noteId: 'n',
        text: 'x',
        due: DateTime(2026, 10, 30),
        done: false,
      );
      await s.syncTaskReminders([task], now: DateTime(2026, 10, 24, 12));
      expect(notifier.scheduledFor('task:t1'), isNotNull);

      // Marca concluída -> some.
      await s.syncTaskReminders(
        [
          TaskReminder(
            id: 't1',
            noteId: 'n',
            text: 'x',
            due: DateTime(2026, 10, 30),
            done: true,
          ),
        ],
        now: DateTime(2026, 10, 24, 12),
      );
      expect(notifier.cancelled, contains('task:t1'));
      expect(notifier.scheduledFor('task:t1'), isNull);
    });
  });

  group('pergunta do diário', () {
    test('agenda às 21h com o texto do prompt', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      await s.scheduleDiaryPrompt(
        prompt: 'Pelo que você é grato hoje?',
        now: DateTime(2026, 10, 24, 12),
      );
      final sch = notifier.scheduledFor('diary-prompt')!;
      expect(sch.when, DateTime(2026, 10, 24, 21));
      expect(sch.body, 'Pelo que você é grato hoje?');
    });

    test('agenda para amanhã se já passou das 21h', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      await s.scheduleDiaryPrompt(
        prompt: 'q',
        now: DateTime(2026, 10, 24, 22),
      );
      expect(
        notifier.scheduledFor('diary-prompt')!.when,
        DateTime(2026, 10, 25, 21),
      );
    });
  });

  group('resumo semanal', () {
    test('agenda para a próxima segunda às 9h', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      // 2026-10-24 é sábado -> próxima segunda 2026-10-26.
      await s.scheduleWeeklySummary(now: DateTime(2026, 10, 24, 12));
      expect(
        notifier.scheduledFor('weekly-summary')!.when,
        DateTime(2026, 10, 26, 9),
      );
    });

    test('shouldGenerateWeeklyNow quando a segunda passou sem gerar', () async {
      final s = NotificationScheduler(
        notifier: notifier,
        settings: await settingsWith({}),
      );
      // Terça 2026-10-27 12h, nunca gerou -> deve gerar.
      expect(s.shouldGenerateWeeklyNow(DateTime(2026, 10, 27, 12)), isTrue);
    });

    test('nextMonday e weekStartOf', () {
      expect(
        NotificationScheduler.nextMonday(DateTime(2026, 10, 24, 12), 9),
        DateTime(2026, 10, 26, 9),
      );
      expect(
        NotificationScheduler.weekStartOf(DateTime(2026, 10, 24)),
        DateTime(2026, 10, 19),
      );
    });
  });
}
