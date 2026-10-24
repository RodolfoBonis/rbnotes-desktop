import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());
  });

  test('generate fetches the summary and records the time', () async {
    final cubit = WeeklySummaryCubit(
      ai: FakeAiClient(thinkDelay: Duration.zero),
      settings: settings,
      now: () => DateTime(2026, 10, 27, 10),
    );
    expect(settings.lastWeeklySummaryAt, isNull);

    await cubit.generate();

    expect(cubit.state.loading, isFalse);
    expect(cubit.state.summary, isNotNull);
    expect(cubit.state.summary!.highlights, isNotEmpty);
    expect(
      settings.lastWeeklySummaryAt!.isAtSameMomentAs(
        DateTime(2026, 10, 27, 10),
      ),
      isTrue,
    );
  });
}
