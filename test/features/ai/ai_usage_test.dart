import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/ai/data/ai_usage.dart';
import 'package:rbnotes/features/ai/data/ai_usage_client.dart';
import 'package:rbnotes/features/ai/data/fake_ai_usage_client.dart';
import 'package:rbnotes/features/ai/presentation/ai_usage_cubit.dart';

class _ThrowingUsageClient implements AiUsageClient {
  @override
  Future<AiUsage> fetch({
    required String from,
    required String to,
    required String tz,
  }) async => throw Exception('boom');
}

void main() {
  group('AiUsage.fromJson', () {
    test('parses the contract example', () {
      final usage = AiUsage.fromJson(const {
        'from': '2026-10-01',
        'to': '2026-10-24',
        'tz': 'America/Sao_Paulo',
        'currency': 'USD',
        'costIsEstimate': true,
        'quota': {'limit': 200, 'used24h': 7},
        'totals': {
          'requests': 42,
          'done': 40,
          'errors': 2,
          'inputTokens': 1000,
          'outputTokens': 500,
          'cacheCreationTokens': 0,
          'cacheReadTokens': 0,
          'costUsd': 1.234567,
          'durationMs': 0,
        },
        'byKind': [
          {'kind': 'note_enrich', 'requests': 30, 'costUsd': 0.9},
        ],
        'days': [
          {
            'date': '2026-10-24',
            'requests': 5,
            'costUsd': 0.12,
            'kinds': [
              {'kind': 'note_enrich', 'requests': 4, 'costUsd': 0.1},
            ],
          },
        ],
      });

      expect(usage.tz, 'America/Sao_Paulo');
      expect(usage.costIsEstimate, isTrue);
      expect(usage.quota.remaining, 193);
      expect(usage.totals.requests, 42);
      expect(usage.totals.totalTokens, 1500);
      expect(usage.byKind.single.kind, 'note_enrich');
      expect(usage.days.single.date, '2026-10-24');
    });

    test('tolerates missing fields', () {
      final usage = AiUsage.fromJson(const {});
      expect(usage.totals.requests, 0);
      expect(usage.days, isEmpty);
      expect(usage.quota.limit, 0);
    });
  });

  test('aiKindLabel translates known kinds', () {
    expect(aiKindLabel('note_enrich'), 'Resumos');
    expect(aiKindLabel('weekly_summary'), 'Resumo semanal');
    expect(aiKindLabel('unknown'), 'unknown');
  });

  group('AiUsageCubit', () {
    final fixedNow = DateTime(2026, 10, 24);

    test('start loads the current month range', () async {
      final cubit = AiUsageCubit(
        client: const FakeAiUsageClient(),
        now: () => fixedNow,
      );
      await cubit.start();
      expect(cubit.state.period, UsagePeriod.thisMonth);
      expect(cubit.state.from, DateTime(2026, 10));
      expect(cubit.state.to, DateTime(2026, 10, 24));
      expect(cubit.state.usage, isNotNull);
      expect(cubit.state.loading, isFalse);
    });

    test('previousMonth computes the full prior month', () async {
      final cubit = AiUsageCubit(
        client: const FakeAiUsageClient(),
        now: () => fixedNow,
      );
      await cubit.selectPeriod(UsagePeriod.previousMonth);
      expect(cubit.state.from, DateTime(2026, 9));
      expect(cubit.state.to, DateTime(2026, 9, 30));
    });

    test('last30Days spans 30 inclusive days', () async {
      final cubit = AiUsageCubit(
        client: const FakeAiUsageClient(),
        now: () => fixedNow,
      );
      await cubit.selectPeriod(UsagePeriod.last30Days);
      expect(cubit.state.from, DateTime(2026, 9, 25));
      expect(cubit.state.to, DateTime(2026, 10, 24));
    });

    test('custom range normalizes order', () async {
      final cubit = AiUsageCubit(
        client: const FakeAiUsageClient(),
        now: () => fixedNow,
      );
      await cubit.setCustomRange(DateTime(2026, 10, 20), DateTime(2026, 10, 5));
      expect(cubit.state.period, UsagePeriod.custom);
      expect(cubit.state.from, DateTime(2026, 10, 5));
      expect(cubit.state.to, DateTime(2026, 10, 20));
    });

    test('surfaces a friendly error when the client throws', () async {
      final cubit = AiUsageCubit(
        client: _ThrowingUsageClient(),
        now: () => fixedNow,
      );
      await cubit.start();
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.loading, isFalse);
    });
  });
}
