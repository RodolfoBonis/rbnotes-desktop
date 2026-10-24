import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_cubit.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_screen.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app({required bool dark}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsStore(await SharedPreferences.getInstance());
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: RbNotesTheme.light(),
    darkTheme: RbNotesTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: BlocProvider(
      create: (_) => WeeklySummaryCubit(
        ai: FakeAiClient(thinkDelay: Duration.zero),
        settings: settings,
      )..generate(),
      child: WeeklySummaryScreen(onClose: () {}),
    ),
  );
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('resumo da semana — ${dark ? 'escuro' : 'claro'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await _app(dark: dark));
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/weekly_summary_${dark ? 'dark' : 'light'}.png',
        ),
      );
    });
  }
}
