import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_exceptions.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/notifications/notification_coordinator.dart';
import 'package:rbnotes/notifications/notification_scheduler.dart';
import 'package:rbnotes/notifications/notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late NoteAiRepository noteAi;
  late FakeNotifier notifier;
  late NotificationScheduler scheduler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = memoryDb();
    notes = memoryRepo(db);
    noteAi = NoteAiRepository(db);
    notifier = FakeNotifier();
  });

  tearDown(() async {
    await notifier.dispose();
    await db.close();
  });

  Future<SettingsStore> buildSettings([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    return SettingsStore(await SharedPreferences.getInstance());
  }

  NotificationCoordinator build(
    _CountingAiClient ai,
    SettingsStore settings, {
    DateTime Function()? now,
  }) {
    scheduler = NotificationScheduler(notifier: notifier, settings: settings);
    return NotificationCoordinator(
      notifier: notifier,
      scheduler: scheduler,
      noteAi: noteAi,
      notes: notes,
      ai: ai,
      settings: settings,
      now: now,
    );
  }

  group('pergunta do diário (cota de IA)', () {
    test('N syncs geram no máximo 1 dailyPrompt para a mesma data', () async {
      final ai = _CountingAiClient();
      final settings = await buildSettings();
      final at = DateTime(2026, 10, 24, 12);
      final coord = build(ai, settings, now: () => at);

      for (var i = 0; i < 50; i++) {
        await coord.rescheduleAll();
      }

      expect(ai.dailyPromptCalls, 1);
      // A notificação continua sendo (re)agendada a partir do cache.
      expect(
        notifier.scheduledFor('diary-prompt')!.body,
        'pergunta de 2026-10-25',
      );
    });

    test('nova data gera uma nova pergunta (1 por data)', () async {
      final ai = _CountingAiClient();
      final settings = await buildSettings();
      var now = DateTime(2026, 10, 24, 12);
      final coord = build(ai, settings, now: () => now);

      await coord.rescheduleAll();
      await coord.rescheduleAll();
      expect(ai.dailyPromptCalls, 1);

      // Vira o dia: "amanhã" muda, então gera exatamente mais uma vez.
      now = DateTime(2026, 10, 25, 12);
      await coord.rescheduleAll();
      await coord.rescheduleAll();
      expect(ai.dailyPromptCalls, 2);
      expect(ai.lastPromptDates, ['2026-10-25', '2026-10-26']);
    });

    test('limite diário faz backoff até o dia seguinte, sem repetir', () async {
      final ai = _CountingAiClient(throwDailyLimit: true);
      final settings = await buildSettings();
      var now = DateTime(2026, 10, 24, 12);
      final coord = build(ai, settings, now: () => now);

      for (var i = 0; i < 10; i++) {
        await coord.rescheduleAll();
      }
      // Tentou uma única vez; o backoff segura os syncs seguintes do dia.
      expect(ai.dailyPromptCalls, 1);
      expect(settings.diaryPromptRetryAt, DateTime(2026, 10, 25).toUtc());

      // Mais tarde no mesmo dia: ainda em backoff.
      now = DateTime(2026, 10, 24, 20);
      await coord.rescheduleAll();
      expect(ai.dailyPromptCalls, 1);

      // No dia seguinte o backoff expira e tenta de novo (uma vez).
      ai.throwDailyLimit = false;
      now = DateTime(2026, 10, 25, 9);
      await coord.rescheduleAll();
      await coord.rescheduleAll();
      expect(ai.dailyPromptCalls, 2);
    });

    test('erro de rede faz backoff de horas, não a cada sync', () async {
      final ai = _CountingAiClient(throwNetwork: true);
      final settings = await buildSettings();
      final now = DateTime(2026, 10, 24, 12);
      final coord = build(ai, settings, now: () => now);

      await coord.rescheduleAll();
      await coord.rescheduleAll();
      expect(ai.dailyPromptCalls, 1);
      expect(settings.diaryPromptRetryAt, DateTime(2026, 10, 24, 16).toUtc());
    });

    test('toggle desligado não chama a IA e cancela a notificação', () async {
      final ai = _CountingAiClient();
      final settings = await buildSettings({
        'settings.notif.diary_prompt': false,
      });
      final coord = build(ai, settings, now: () => DateTime(2026, 10, 24, 12));

      await coord.rescheduleAll();
      expect(ai.dailyPromptCalls, 0);
      expect(notifier.cancelled, contains('diary-prompt'));
    });

    test(
      'cache sobrevive a uma nova instância (persistido por data)',
      () async {
        final settings = await buildSettings();
        final at = DateTime(2026, 10, 24, 12);

        final ai1 = _CountingAiClient();
        await build(ai1, settings, now: () => at).rescheduleAll();
        expect(ai1.dailyPromptCalls, 1);

        // Reinício do app com as mesmas prefs: não chama a IA de novo.
        final reopened = SettingsStore(await SharedPreferences.getInstance());
        final ai2 = _CountingAiClient();
        await build(ai2, reopened, now: () => at).rescheduleAll();
        expect(ai2.dailyPromptCalls, 0);
      },
    );
  });
}

/// AiClient de teste que conta `dailyPrompt` e pode simular erros de cota/rede.
class _CountingAiClient implements AiClient {
  _CountingAiClient({this.throwDailyLimit = false, this.throwNetwork = false});

  bool throwDailyLimit;
  bool throwNetwork;
  int dailyPromptCalls = 0;
  final List<String> lastPromptDates = [];

  @override
  Future<String> dailyPrompt(DateTime date) async {
    dailyPromptCalls++;
    final ymd =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    lastPromptDates.add(ymd);
    if (throwDailyLimit) throw const AiDailyLimitException();
    if (throwNetwork) throw const AiException('rede');
    return 'pergunta de $ymd';
  }

  @override
  Future<NoteAi> enrich(EnrichRequest request) => throw UnimplementedError();

  @override
  Stream<AiDelta> chat({
    required String noteId,
    required List<AiSegment> segments,
    required List<String> speakers,
    required String message,
    bool ephemeral = false,
  }) => throw UnimplementedError();

  @override
  Stream<AiDelta> ask({
    required String question,
    required List<AskCandidate> candidates,
  }) => throw UnimplementedError();

  @override
  Future<CollectionRuleResult> collectionRule(String description) =>
      throw UnimplementedError();

  @override
  Future<DiaryMonth> diaryMonth({
    required String month,
    required List<String> entries,
  }) => throw UnimplementedError();

  @override
  Future<WeeklySummary> weeklySummary({
    required DateTime weekStart,
    required String tz,
  }) => throw UnimplementedError();
}
