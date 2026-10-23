import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/presentation/settings_cubit.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_db.dart';

void main() {
  late FakeRbNative native;
  late SettingsStore store;
  late DictationService dictation;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    native = FakeRbNative();
    final prefs = await SharedPreferences.getInstance();
    store = SettingsStore(prefs);
    dictation = DictationService(
      native: native,
      repository: memoryRepo(memoryDb()),
      settings: store,
    );
  });

  tearDown(() => native.dispose());

  SettingsCubit build() =>
      SettingsCubit(store: store, native: native, dictation: dictation);

  test('refreshPermissions coleta o status de cada permissão', () async {
    final cubit = build();
    await cubit.refreshPermissions();
    expect(
      cubit.state.statusOf(RbPermission.microphone),
      PermissionStatus.granted,
    );
  });

  test('setCaptureSystemAudio persiste e emite', () async {
    final cubit = build();
    await cubit.setCaptureSystemAudio(value: true);
    expect(cubit.state.captureSystemAudio, isTrue);
    expect(store.captureSystemAudio, isTrue);
  });

  test('setHotkey re-registra o atalho no nativo', () async {
    final cubit = build();
    const hotkey = Hotkey(keyCode: 49, modifiers: {HotkeyModifier.command});
    await cubit.setHotkey(hotkey);
    expect(store.hotkey, hotkey);
    expect(native.registeredHotkey, hotkey);
  });

  test('setDictationEnabled false desregistra o atalho', () async {
    final cubit = build();
    await cubit.setDictationEnabled(value: false);
    expect(native.registeredHotkey, isNull);
  });
}
