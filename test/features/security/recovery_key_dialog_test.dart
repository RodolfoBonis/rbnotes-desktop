import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/security/data/note_key.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';
import 'package:rbnotes/features/settings/presentation/recovery_key_dialog.dart';

Future<void> _pump(
  WidgetTester tester,
  NoteKeyStore store, {
  VoidCallback? onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: RbNotesTheme.light(),
      home: Scaffold(
        body: RecoveryKeyDialog(keyStore: store, onKeyChanged: onChanged),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final key = NoteKey(Uint8List.fromList(List.generate(32, (i) => i)));

  testWidgets('shows a hint when no key exists yet', (tester) async {
    await _pump(tester, InMemoryNoteKeyStore());
    expect(find.textContaining('Nenhuma chave ainda'), findsOneWidget);
  });

  testWidgets('reveals the recovery key on demand', (tester) async {
    await _pump(tester, InMemoryNoteKeyStore(key));
    // Masked by default; reveal shows the real grouped base32.
    expect(find.text(key.recovery), findsNothing);
    await tester.tap(find.text('Mostrar'));
    await tester.pump();
    expect(find.text(key.recovery), findsOneWidget);
  });

  testWidgets('imports a valid recovery key and notifies', (tester) async {
    final store = InMemoryNoteKeyStore();
    var changed = 0;
    await _pump(tester, store, onChanged: () => changed++);

    await tester.enterText(
      find.byKey(const Key('recovery-import-field')),
      key.recovery,
    );
    await tester.tap(find.byKey(const Key('recovery-import-button')));
    await tester.pumpAndSettle();

    expect(changed, 1);
    expect(await store.load(), key);
    expect(find.textContaining('importada e testada'), findsOneWidget);
  });

  testWidgets('rejects an invalid recovery key', (tester) async {
    final store = InMemoryNoteKeyStore();
    await _pump(tester, store);
    await tester.enterText(
      find.byKey(const Key('recovery-import-field')),
      'NOT-A-VALID-KEY',
    );
    await tester.tap(find.byKey(const Key('recovery-import-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('inválida'), findsOneWidget);
    expect(await store.hasKey(), isFalse);
  });
}
