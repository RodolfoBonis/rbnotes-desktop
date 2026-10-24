import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsStore> _settings({required bool touchId}) async {
  SharedPreferences.setMockInitialValues({'settings.touch_id': touchId});
  return SettingsStore(await SharedPreferences.getInstance());
}

void main() {
  late FakeRbNative native;

  setUp(() => native = FakeRbNative());
  tearDown(() => native.dispose());

  test('starts locked when Touch ID lock is enabled', () async {
    final cubit = AppLockCubit(
      native: native,
      auth: FakeBiometricAuth(),
      settings: await _settings(touchId: true),
    );
    expect(cubit.state.enabled, isTrue);
    expect(cubit.state.locked, isTrue);
  });

  test('starts unlocked when disabled', () async {
    final cubit = AppLockCubit(
      native: native,
      auth: FakeBiometricAuth(),
      settings: await _settings(touchId: false),
    );
    expect(cubit.state.locked, isFalse);
  });

  test('a native lock trigger locks the app when enabled', () async {
    final cubit = AppLockCubit(
      native: native,
      auth: FakeBiometricAuth(),
      settings: await _settings(touchId: true),
    );
    await cubit.unlock();
    expect(cubit.state.locked, isFalse);

    native.emitLockTrigger(LockTrigger.screenLocked);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.locked, isTrue);
  });

  test('lock triggers are ignored when the lock is disabled', () async {
    final cubit = AppLockCubit(
      native: native,
      auth: FakeBiometricAuth(),
      settings: await _settings(touchId: false),
    );
    native.emitLockTrigger(LockTrigger.systemSleep);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.locked, isFalse);
  });

  test('unlock succeeds with biometrics and fails otherwise', () async {
    final auth = FakeBiometricAuth(result: false);
    final cubit = AppLockCubit(
      native: native,
      auth: auth,
      settings: await _settings(touchId: true),
    );
    expect(await cubit.unlock(), isFalse);
    expect(cubit.state.locked, isTrue);

    auth.result = true;
    expect(await cubit.unlock(), isTrue);
    expect(cubit.state.locked, isFalse);
  });

  test('disabling the lock unlocks immediately', () async {
    final cubit = AppLockCubit(
      native: native,
      auth: FakeBiometricAuth(),
      settings: await _settings(touchId: true),
    );
    await cubit.setEnabled(enabled: false);
    expect(cubit.state.enabled, isFalse);
    expect(cubit.state.locked, isFalse);
  });
}
