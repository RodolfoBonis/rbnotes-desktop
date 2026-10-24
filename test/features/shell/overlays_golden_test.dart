import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rbnotes/app/shell/app_shell.dart';
import 'package:rbnotes/app/shell/shell_overlay_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';

import '../../helpers/shell_harness.dart';

class _MockRecordingCubit extends MockCubit<RecordingState>
    implements RecordingCubit {}

void main() {
  late ShellHarness harness;

  setUp(() {
    harness = ShellHarness();
  });

  Future<void> boot(
    WidgetTester tester, {
    bool dark = false,
    RecordingCubit? recording,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(harness.setUp);
    await tester.pumpWidget(harness.app(dark: dark, recording: recording));
    await harness.settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  Future<void> down(WidgetTester tester) => tester.runAsync(harness.tearDown);

  ShellOverlayCubit overlay(WidgetTester tester) =>
      tester.element(find.byType(AppShell)).read<ShellOverlayCubit>();

  testWidgets('nota — tema escuro', (tester) async {
    await boot(tester, dark: true);
    await shot(tester, 'note_dark');
    await down(tester);
  });

  testWidgets('nova coleção', (tester) async {
    await boot(tester);
    overlay(tester).openNewCollection();
    await harness.settle(tester);
    await shot(tester, 'new_collection');
    await down(tester);
  });

  testWidgets('corrigir palavra', (tester) async {
    await boot(tester);
    overlay(tester).openFix('Taís');
    await harness.settle(tester);
    await shot(tester, 'fix_word');
    await down(tester);
  });

  for (final (label, name) in const <(String, String)>[
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
      overlay(tester).openSettings();
      await harness.settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(SettingsModal),
          matching: find.text(label),
        ),
      );
      await harness.settle(tester);
      await shot(tester, name);
      await down(tester);
    });
  }

  testWidgets('HUD de gravação', (tester) async {
    final rec = _MockRecordingCubit();
    const state = RecordingState(
      status: RecordingStatus.recording,
      elapsed: Duration(seconds: 14),
      micLevel: 0.55,
      liveText:
          '…a ideia é testar o protótipo com cinco pessoas antes de '
          'sexta e ajustar o fluxo',
    );
    whenListen(rec, const Stream<RecordingState>.empty(), initialState: state);
    when(() => rec.createdNotes).thenAnswer((_) => const Stream.empty());
    await boot(tester, recording: rec);
    await shot(tester, 'recording_hud');
    await down(tester);
  });

  testWidgets('HUD de processamento', (tester) async {
    final rec = _MockRecordingCubit();
    const state = RecordingState(
      status: RecordingStatus.processing,
      noteId: 'n1',
      step: 2,
      stepProgress: 0.6,
    );
    whenListen(rec, const Stream<RecordingState>.empty(), initialState: state);
    when(() => rec.createdNotes).thenAnswer((_) => const Stream.empty());
    await boot(tester, recording: rec);
    await shot(tester, 'processing_hud');
    await down(tester);
  });

  testWidgets('HUD de processamento — erro', (tester) async {
    final rec = _MockRecordingCubit();
    const state = RecordingState(
      status: RecordingStatus.processing,
      noteId: 'n1',
      failedStep: 0,
      error: 'Não foi possível transcrever.',
    );
    whenListen(rec, const Stream<RecordingState>.empty(), initialState: state);
    when(() => rec.createdNotes).thenAnswer((_) => const Stream.empty());
    await boot(tester, recording: rec);
    await shot(tester, 'processing_hud_error');
    await down(tester);
  });
}
