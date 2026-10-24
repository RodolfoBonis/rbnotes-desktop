import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/recording/data/record_note_hotkey_service.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeRbNative native;
  late SettingsStore settings;
  late RecordNoteHotkeyService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    native = FakeRbNative();
    settings = SettingsStore(await SharedPreferences.getInstance());
    service = RecordNoteHotkeyService(native: native, settings: settings);
  });

  tearDown(() async {
    await service.dispose();
    await native.dispose();
  });

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'start registers record_note with the default ⌥⇧Espaço hotkey',
    () async {
      await service.start();

      expect(
        native.registeredGlobalHotkeys[RecordNoteHotkeyService.hotkeyId],
        SettingsStore.defaultRecordHotkey,
      );
      expect(service.status.registered, isTrue);
      expect(service.status.hasError, isFalse);
    },
  );

  test('disabled hotkey is not registered', () async {
    await settings.setRecordHotkeyEnabled(value: false);

    await service.start();

    expect(
      native.registeredGlobalHotkeys.containsKey(
        RecordNoteHotkeyService.hotkeyId,
      ),
      isFalse,
    );
    expect(service.status.registered, isFalse);
  });

  test('pressing the record_note hotkey invokes onTriggered', () async {
    var triggered = 0;
    service.onTriggered = () async => triggered++;
    await service.start();

    native.emitGlobalHotkey(RecordNoteHotkeyService.hotkeyId);
    await pump();

    expect(triggered, 1);
  });

  test('a press for a different id is ignored', () async {
    var triggered = 0;
    service.onTriggered = () async => triggered++;
    await service.start();

    native.emitGlobalHotkey('some_other_hotkey');
    await pump();

    expect(triggered, 0);
  });

  test('registration failure surfaces as an error status', () async {
    native.globalHotkeyRegisterError = const RbNativeException(
      RbNativeErrorCode.hotkeyConflict,
      'hotkey is already used by the dictation shortcut',
    );

    final statuses = <RecordNoteHotkeyStatus>[];
    final sub = service.statusChanges.listen(statuses.add);
    await service.start();
    await pump();
    await sub.cancel();

    expect(service.status.registered, isFalse);
    expect(service.status.hasError, isTrue);
    expect(service.status.error, contains('dictation'));
    expect(statuses.last.hasError, isTrue);
  });

  test('applySettings re-registers with the updated hotkey', () async {
    await service.start();

    // Rebind to ⌃R (control + R, keyCode 15).
    const rebound = Hotkey(
      keyCode: 15,
      modifiers: {HotkeyModifier.control},
    );
    await settings.setRecordHotkey(rebound);
    await service.applySettings();

    expect(
      native.registeredGlobalHotkeys[RecordNoteHotkeyService.hotkeyId],
      rebound,
    );
  });

  test('dispose unregisters the hotkey', () async {
    await service.start();
    expect(
      native.registeredGlobalHotkeys.containsKey(
        RecordNoteHotkeyService.hotkeyId,
      ),
      isTrue,
    );

    await service.dispose();

    expect(
      native.registeredGlobalHotkeys.containsKey(
        RecordNoteHotkeyService.hotkeyId,
      ),
      isFalse,
    );
    // Re-dispose in tearDown must be safe (controller already closed).
  });
}
