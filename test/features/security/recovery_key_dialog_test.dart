import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/security/data/note_cipher.dart';
import 'package:rbnotes/features/security/data/note_key.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';
import 'package:rbnotes/features/settings/presentation/recovery_key_dialog.dart';

Future<void> _pump(
  WidgetTester tester,
  NoteKeyStore store, {
  VoidCallback? onChanged,
  Future<Map<String, dynamic>?> Function()? loadKeyCheck,
  Future<void> Function(Map<String, dynamic>)? saveKeyCheck,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: RbNotesTheme.light(),
      home: Scaffold(
        body: RecoveryKeyDialog(
          keyStore: store,
          onKeyChanged: onChanged,
          loadKeyCheck: loadKeyCheck,
          saveKeyCheck: saveKeyCheck,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  _unitTests();
  final key = NoteKey(Uint8List.fromList(List.generate(32, (i) => i)));
  final otherKey = NoteKey(Uint8List.fromList(List.generate(32, (i) => 7)));

  testWidgets('shows a hint when no key exists yet', (tester) async {
    await _pump(tester, InMemoryNoteKeyStore());
    expect(find.textContaining('Nenhuma chave ainda'), findsOneWidget);
  });

  testWidgets('reveals the recovery key on demand', (tester) async {
    await _pump(tester, InMemoryNoteKeyStore(key));
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

  // M10: valida contra o sentinela — uma chave que não abre é recusada.
  testWidgets('rejects a well-formed key that does not open the notes', (
    tester,
  ) async {
    final sentinel = await NoteCipher(
      key,
    ).encrypt({'check': 'rbnotes-key-check'});
    final store = InMemoryNoteKeyStore();
    await _pump(
      tester,
      store,
      loadKeyCheck: () async => sentinel,
    );
    await tester.enterText(
      find.byKey(const Key('recovery-import-field')),
      otherKey.recovery,
    );
    await tester.tap(find.byKey(const Key('recovery-import-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('não abre suas notas'), findsOneWidget);
    expect(await store.hasKey(), isFalse);
  });

  testWidgets('accepts the key that opens the sentinel and saves a new one', (
    tester,
  ) async {
    final sentinel = await NoteCipher(
      key,
    ).encrypt({'check': 'rbnotes-key-check'});
    final store = InMemoryNoteKeyStore();
    Map<String, dynamic>? saved;
    await _pump(
      tester,
      store,
      loadKeyCheck: () async => sentinel,
      saveKeyCheck: (e) async => saved = e,
    );
    await tester.enterText(
      find.byKey(const Key('recovery-import-field')),
      key.recovery,
    );
    await tester.tap(find.byKey(const Key('recovery-import-button')));
    await tester.pumpAndSettle();

    expect(await store.load(), key);
    expect(saved, isNotNull, reason: 'um novo sentinela foi gravado');
  });

  // M10: confirma antes de sobrescrever uma chave existente.
  testWidgets('asks for confirmation before overwriting an existing key', (
    tester,
  ) async {
    final sentinel = await NoteCipher(
      otherKey,
    ).encrypt({'check': 'rbnotes-key-check'});
    final store = InMemoryNoteKeyStore(key); // já há uma chave neste Mac
    await _pump(
      tester,
      store,
      loadKeyCheck: () async => sentinel,
      saveKeyCheck: (_) async {},
    );
    await tester.enterText(
      find.byKey(const Key('recovery-import-field')),
      otherKey.recovery,
    );
    await tester.tap(find.byKey(const Key('recovery-import-button')));
    await tester.pumpAndSettle();

    // Pede confirmação; antes de confirmar, a chave não mudou.
    expect(find.text('Substituir a chave deste Mac?'), findsOneWidget);
    expect(await store.load(), key);

    await tester.tap(find.text('Substituir'));
    await tester.pumpAndSettle();
    expect(await store.load(), otherKey);
  });

}

void _unitTests() {
  group('clearRecoveryClipboard (M13)', () {
    final key = NoteKey(Uint8List.fromList(List.generate(32, (i) => i)));

    test('clears the clipboard when it still holds the key', () async {
      var cleared = false;
      await clearRecoveryClipboard(
        key.recovery,
        read: () async => ClipboardData(text: key.recovery),
        write: (d) async => cleared = (d.text ?? '').isEmpty,
      );
      expect(cleared, isTrue);
    });

    test('does not clear when the clipboard changed meanwhile', () async {
      var wrote = false;
      await clearRecoveryClipboard(
        key.recovery,
        read: () async => const ClipboardData(text: 'outra coisa'),
        write: (_) async => wrote = true,
      );
      expect(wrote, isFalse);
    });
  });
}
