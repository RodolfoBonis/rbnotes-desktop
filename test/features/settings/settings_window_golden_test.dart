import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/app/accent_cubit.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';

import '../../helpers/shell_harness.dart';

/// Goldens for the Settings UI as it renders inside the native Settings window
/// (the chromeless body — the window itself provides the title bar / traffic
/// lights). Mirrors the panes the old in-window modal used to cover.
void main() {
  late ShellHarness harness;

  setUp(() => harness = ShellHarness());

  Widget body() => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => ThemeModeCubit(di())),
      BlocProvider(create: (_) => AccentCubit(di())),
      BlocProvider(
        create: (_) => AppLockCubit(
          native: di(),
          auth: FakeBiometricAuth(),
          settings: di(),
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RbNotesTheme.light(),
      darkTheme: RbNotesTheme.dark(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SettingsModal(
        store: di(),
        native: di(),
        vocabulary: di(),
        recordNoteHotkey: di(),
        aiUsageClient: di(),
        noteKeyStore: di(),
        notifier: di(),
        notes: di(),
        userName: 'Renata Borges',
        userEmail: 'renata@borges.studio',
        userInitials: 'RB',
        onClose: () {},
        onLogout: ({required wipe}) async {},
        onEraseAllData: () async {},
      ),
    ),
  );

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 580);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(harness.setUp);
    await tester.pumpWidget(body());
    await harness.settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) => expectLater(
    find.byType(SettingsModal),
    matchesGoldenFile('goldens/$name.png'),
  );

  for (final (label, name) in const <(String, String)>[
    ('Geral', 'settings_general'),
    ('Gravação', 'settings_recording'),
    ('Transcrição', 'settings_transcription'),
    ('Inteligência', 'settings_intelligence'),
    ('Conta', 'settings_account'),
    ('Uso', 'settings_usage'),
    ('Atalhos', 'settings_shortcuts'),
    ('Privacidade', 'settings_privacy'),
  ]) {
    testWidgets('configurações — $label', (tester) async {
      await boot(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(SettingsModal),
          matching: find.text(label),
        ),
      );
      await harness.settle(tester);
      await shot(tester, name);
      await tester.runAsync(harness.tearDown);
    });
  }
}
