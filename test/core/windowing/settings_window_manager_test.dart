import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/windowing/fake_settings_window.dart';

void main() {
  group('SettingsWindowManager', () {
    test('openOrFocus creates the window once, with the initial title', () {
      final created = <FakeNativeWindow>[];
      final manager = fakeSettingsWindowManager(onCreate: created.add);

      expect(manager.isOpen, isFalse);
      manager.openOrFocus();

      expect(manager.isOpen, isTrue);
      expect(created, hasLength(1));
      expect(created.single.title, 'Geral');
      expect(created.single.activateCount, 0);
    });

    test('openOrFocus on an open window focuses it (single instance)', () {
      final created = <FakeNativeWindow>[];
      final manager = fakeSettingsWindowManager(onCreate: created.add)
        ..openOrFocus()
        ..openOrFocus()
        ..openOrFocus();

      // Only ever one window; extra calls just re-activate it.
      expect(manager.isOpen, isTrue);
      expect(created, hasLength(1));
      expect(created.single.activateCount, 2);
    });

    test('close destroys the window and allows reopening a fresh one', () {
      final created = <FakeNativeWindow>[];
      final manager = fakeSettingsWindowManager(onCreate: created.add)
        ..openOrFocus();
      final first = created.single;

      manager.close();
      expect(manager.isOpen, isFalse);
      expect(first.destroyed, isTrue);

      manager.openOrFocus();
      expect(created, hasLength(2));
      expect(manager.isOpen, isTrue);
      expect(created.last.destroyed, isFalse);
    });

    test('a native close request clears the single-instance state', () {
      // The real window invokes onCloseRequested (red button / ⌘W); the
      // manager wires that to close(). We simulate that routing here.
      final created = <FakeNativeWindow>[];
      final manager = fakeSettingsWindowManager(onCreate: created.add)
        ..openOrFocus()
        ..close();

      expect(manager.isOpen, isFalse);
      expect(created.single.destroyed, isTrue);

      manager.openOrFocus();
      expect(manager.isOpen, isTrue);
    });

    test('setTitle forwards to the live window and is a no-op when closed', () {
      final created = <FakeNativeWindow>[];
      fakeSettingsWindowManager(onCreate: created.add)
        // No window yet: must not throw.
        ..setTitle('Gravação')
        ..openOrFocus()
        ..setTitle('Transcrição');

      expect(created.single.title, 'Transcrição');
    });

    test(
      'reopening after the window died (isAlive false) creates a new one',
      () {
        final created = <FakeNativeWindow>[];
        final manager = fakeSettingsWindowManager(onCreate: created.add)
          ..openOrFocus();

        // Window went away without routing through the manager.
        created.single.destroy();

        manager.openOrFocus();
        expect(created, hasLength(2));
      },
    );
  });
}
