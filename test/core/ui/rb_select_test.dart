import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/ui/rb_select.dart';

import '../../helpers/golden.dart';

Widget _harness({
  required String value,
  required List<String> options,
  required ValueChanged<String> onChanged,
}) => Scaffold(
  backgroundColor: const Color(0xFFF2F2F7),
  body: Padding(
    padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 160,
        child: RbSelect<String>(
          value: value,
          options: options,
          onChanged: onChanged,
        ),
      ),
    ),
  ),
);

void main() {
  const options = [
    'Trabalho',
    'Pessoal',
    'Estudos',
    'Ideias',
    'Diário',
  ];

  testWidgets('abre o menu ao tocar e seleciona com clique', (tester) async {
    String? picked;
    await pumpScreen(
      tester,
      _harness(
        value: 'Ideias',
        options: options,
        onChanged: (v) => picked = v,
      ),
      size: const Size(360, 360),
    );

    expect(find.text('Estudos'), findsNothing); // menu fechado
    await tester.tap(find.byType(RbSelect<String>));
    await tester.pumpAndSettle();
    expect(find.text('Estudos'), findsOneWidget); // menu aberto

    await tester.tap(find.text('Pessoal'));
    await tester.pumpAndSettle();
    expect(picked, 'Pessoal');
    expect(find.text('Estudos'), findsNothing); // fechou
  });

  testWidgets('navega por setas e confirma com Enter', (tester) async {
    String? picked;
    await pumpScreen(
      tester,
      _harness(
        value: 'Trabalho',
        options: options,
        onChanged: (v) => picked = v,
      ),
      size: const Size(360, 360),
    );
    await tester.tap(find.byType(RbSelect<String>));
    await tester.pumpAndSettle();

    // Começa em "Trabalho" (0); desce 2 -> "Estudos".
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, 'Estudos');
  });

  testWidgets('Esc fecha sem selecionar', (tester) async {
    String? picked;
    await pumpScreen(
      tester,
      _harness(
        value: 'Trabalho',
        options: options,
        onChanged: (v) => picked = v,
      ),
      size: const Size(360, 360),
    );
    await tester.tap(find.byType(RbSelect<String>));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.text('Estudos'), findsNothing);
  });

  for (final dark in [false, true]) {
    final name = dark ? 'rb_select_open_dark' : 'rb_select_open';
    testWidgets('golden do menu aberto ($name)', (tester) async {
      await pumpScreen(
        tester,
        _harness(value: 'Ideias', options: options, onChanged: (_) {}),
        size: const Size(360, 360),
        dark: dark,
      );
      await tester.tap(find.byType(RbSelect<String>));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
