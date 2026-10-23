import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';

/// Tamanho da janela do design (o mock tem 1280×800).
const goldenSize = Size(1280, 800);

/// Monta [child] numa `MaterialApp` com o tema RbNotes (claro ou escuro) no
/// tamanho da janela do design, pronto para `matchesGoldenFile`.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
  Size size = goldenSize,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RbNotesTheme.light,
      darkTheme: RbNotesTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}
