import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/security/presentation/lock_screen.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app({required bool dark}) async {
  SharedPreferences.setMockInitialValues({'settings.touch_id': true});
  final settings = SettingsStore(await SharedPreferences.getInstance());
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: RbNotesTheme.light(),
    darkTheme: RbNotesTheme.dark(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    home: BlocProvider(
      create: (_) => AppLockCubit(
        native: FakeRbNative(),
        auth: FakeBiometricAuth(),
        settings: settings,
      ),
      child: Builder(
        builder: (context) => Stack(
          children: [
            const Scaffold(body: Center(child: Text('conteúdo secreto'))),
            const LockScreen(),
          ],
        ),
      ),
    ),
  );
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('tela de bloqueio — ${dark ? 'escuro' : 'claro'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await _app(dark: dark));
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/lock_screen_${dark ? 'dark' : 'light'}.png',
        ),
      );
    });
  }
}
