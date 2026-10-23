import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late FakeRbNative native;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    native = FakeRbNative(modelDownloaded: false);
    settings = SettingsStore(await SharedPreferences.getInstance());
  });

  tearDown(() async => native.dispose());

  OnboardingCubit build() =>
      OnboardingCubit(native: native, settings: settings);

  test('next não avança da etapa de permissões sem o microfone', () async {
    final cubit = build()..next(); // 0 -> 1
    expect(cubit.state.step, 1);
    cubit.next(); // bloqueado: mic não concedido
    expect(cubit.state.step, 1);
    await cubit.close();
  });

  test('conceder microfone libera o avanço', () async {
    final cubit = build()..next();
    await cubit.requestPermission(OnbPerm.mic);
    expect(cubit.state.micGranted, isTrue);
    cubit.next();
    expect(cubit.state.step, 2);
    await cubit.close();
  });

  test(
    'baixar o modelo avança para a etapa final e persiste o modelo',
    () async {
      final cubit = build();
      await cubit.requestPermission(OnbPerm.mic);
      cubit
        ..selectModel(WhisperModel.smallQ5)
        ..next() // 0 -> 1
        ..next() // 1 -> 2 (mic ok)
        ..next(); // inicia download
      // Aguarda o download simulado concluir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(cubit.state.step, 3);
      expect(settings.model, WhisperModel.smallQ5);
      await cubit.close();
    },
  );

  test('voltar retorna à etapa anterior', () async {
    final cubit = build()
      ..next()
      ..back();
    expect(cubit.state.step, 0);
    await cubit.close();
  });
}
