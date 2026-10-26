import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/app/shell/app_shell.dart';

import '../../helpers/shell_harness.dart';

void main() {
  late ShellHarness harness;

  setUp(() {
    harness = ShellHarness();
  });

  Future<void> boot(WidgetTester tester, {bool dark = false}) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(harness.setUp);
    await tester.pumpWidget(harness.app(dark: dark));
    await harness.settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  Future<void> down(WidgetTester tester) => tester.runAsync(harness.tearDown);

  testWidgets('transcrição', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Transcrição'));
    await harness.settle(tester);
    await shot(tester, 'note_transcription');
    await down(tester);
  });

  testWidgets('insights', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Insights'));
    await harness.settle(tester);
    await shot(tester, 'note_insights');
    await down(tester);
  });

  testWidgets('conversa', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Conversa'));
    await harness.settle(tester);
    await shot(tester, 'note_conversa');
    await down(tester);
  });

  testWidgets('diário', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Diário'));
    await harness.settle(tester);
    await shot(tester, 'diary');
    await down(tester);
  });

  testWidgets('tarefas esquecidas', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Tarefas esquecidas'));
    await harness.settle(tester);
    await shot(tester, 'tasks');
    await down(tester);
  });

  testWidgets('perguntar às notas', (tester) async {
    await boot(tester);
    await tester.tap(find.text('Perguntar às notas'));
    await harness.settle(tester);
    await shot(tester, 'ask');
    await down(tester);
  });
}
