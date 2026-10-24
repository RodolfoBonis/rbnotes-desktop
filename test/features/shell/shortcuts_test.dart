import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/app/accent_cubit.dart';
import 'package:rbnotes/app/shell/app_shell.dart';
import 'package:rbnotes/app/shell/overlays.dart';
import 'package:rbnotes/app/shell/shell_overlay_cubit.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/diagnostics_monitor.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_usage_client.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/ai/data/fake_ai_usage_client.dart';
import 'package:rbnotes/features/ai/presentation/ask_cubit.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/auth/presentation/session_cubit.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/diary/presentation/diary_cubit.dart';
import 'package:rbnotes/features/library/data/demo_seeder.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/recording/data/record_note_hotkey_service.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late FakeRbNative native;
  late FakeAuthService auth;
  late Directory tmp;

  Future<void> setup() async {
    if (di.isRegistered<AppDatabase>()) await di.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = memoryDb();
    native = FakeRbNative();
    auth = FakeAuthService();
    await auth.signInWithEmail('renata@borges.studio', 'x');
    tmp = await Directory.systemTemp.createTemp('rbnotes_keys');
    final settings = SettingsStore(prefs);
    final notes = NoteRepository(db);
    final noteAi = NoteAiRepository(db);
    final library = LibraryRepository(db);
    final diary = DiaryRepository(db);
    final ai = FakeAiClient(
      stepDelay: Duration.zero,
      thinkDelay: Duration.zero,
    );
    final queue = TranscriptionQueue(
      native: native,
      repository: notes,
      settings: settings,
      vocabulary: VocabularyRepository(db),
    );
    di
      ..registerSingleton<SharedPreferences>(prefs)
      ..registerSingleton<AppDatabase>(db)
      ..registerSingleton<RbNative>(native)
      ..registerSingleton<AppPaths>(AppPaths.forTesting(tmp))
      ..registerSingleton<SettingsStore>(settings)
      ..registerSingleton<NoteRepository>(notes)
      ..registerSingleton<NoteAiRepository>(noteAi)
      ..registerSingleton<LibraryRepository>(library)
      ..registerSingleton<DiaryRepository>(diary)
      ..registerSingleton<VocabularyRepository>(VocabularyRepository(db))
      ..registerSingleton<AiClient>(ai)
      ..registerSingleton<AiUsageClient>(const FakeAiUsageClient())
      ..registerSingleton<TranscriptionQueue>(queue)
      ..registerSingleton<AuthService>(auth)
      ..registerSingleton<DiagnosticsMonitor>(DiagnosticsMonitor(native))
      ..registerSingleton<RecordNoteHotkeyService>(
        RecordNoteHotkeyService(native: native, settings: settings),
      )
      ..registerFactory<AudioPlayerController>(FakeAudioPlayer.new);
    await DemoSeeder(
      notes: notes,
      noteAi: noteAi,
      library: library,
      diary: diary,
    ).seedIfEmpty();
  }

  Widget harness() => MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => ThemeModeCubit(di())),
      BlocProvider(create: (_) => AccentCubit(di())),
      BlocProvider(
        create: (_) => AppLockCubit(
          native: native,
          auth: FakeBiometricAuth(),
          settings: di(),
        ),
      ),
      BlocProvider(
        create: (_) => SessionCubit(auth: di(), prefs: di()),
      ),
      BlocProvider(
        create: (_) => RecordingCubit(
          native: di(),
          repository: di(),
          queue: di(),
          settings: di(),
          paths: di(),
          diagnostics: native.diagnostics(),
        ),
      ),
      BlocProvider(
        create: (_) => LibraryCubit(notes: di(), noteAi: di(), library: di()),
      ),
      BlocProvider(
        create: (_) => NoteViewCubit(
          notes: di(),
          noteAi: di(),
          ai: di(),
          native: di(),
          player: di(),
        ),
      ),
      BlocProvider(
        create: (_) => AskCubit(ai: di(), notes: di(), noteAi: di()),
      ),
      BlocProvider(create: (_) => ShellOverlayCubit()),
      BlocProvider(
        create: (_) => DiaryCubit(
          diary: di(),
          notes: di(),
          noteAi: di(),
          ai: di(),
          settings: di(),
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RbNotesTheme.light(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppShell(),
    ),
  );

  testWidgets('⌘K abre/fecha Perguntar e ⌘, abre Configurações', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(setup);
    await tester.pumpWidget(harness());
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 40));
    }

    // ⌘K abre o overlay "Perguntar às notas".
    await _meta(tester, LogicalKeyboardKey.keyK);
    await tester.pump();
    expect(find.byType(AskOverlay), findsOneWidget);

    // Esc fecha.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(AskOverlay), findsNothing);

    // ⌘, abre as Configurações.
    await _meta(tester, LogicalKeyboardKey.comma);
    await tester.pump();
    expect(find.byType(SettingsModal), findsOneWidget);

    // Esc fecha.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(SettingsModal), findsNothing);

    await tester.runAsync(() async {
      await native.dispose();
      await auth.dispose();
      await db.close();
      await di.reset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
  });
}

Future<void> _meta(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
}
