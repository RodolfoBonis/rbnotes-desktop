import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/app/accent_cubit.dart';
import 'package:rbnotes/core/theme/accent_presets.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());
  });

  test('starts from the persisted accent (default = Laranja)', () {
    final cubit = AccentCubit(settings);
    expect(cubit.state, AccentPresets.laranja.color);
    expect(cubit.selectedPreset?.id, 'laranja');
  });

  blocTest<AccentCubit, Color>(
    'selectPreset emits and persists the preset color',
    build: () => AccentCubit(settings),
    act: (c) => c.selectPreset(AccentPresets.azul),
    expect: () => [AccentPresets.azul.color],
    verify: (_) {
      expect(settings.accentColor, AccentPresets.azul.color);
    },
  );

  blocTest<AccentCubit, Color>(
    'setColor with a custom color clears the preset mapping',
    build: () => AccentCubit(settings),
    act: (c) => c.setColor(const Color(0xFF112233)),
    expect: () => [const Color(0xFF112233)],
    verify: (c) {
      expect(c.selectedPreset, isNull);
      expect(settings.accentColor, const Color(0xFF112233));
    },
  );

  blocTest<AccentCubit, Color>(
    'setting the same color is a no-op (no emit)',
    build: () => AccentCubit(settings),
    act: (c) => c.selectPreset(AccentPresets.laranja),
    expect: () => <Color>[],
  );
}
