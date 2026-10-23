import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/auth/presentation/login_cubit.dart';
import 'package:rbnotes/features/auth/presentation/login_page.dart';

import '../../helpers/golden.dart';

void main() {
  Widget subject() => BlocProvider(
    create: (_) => LoginCubit(FakeAuthService()),
    child: const LoginPage(),
  );

  testWidgets('login — light', (tester) async {
    await pumpScreen(tester, subject());
    await expectLater(
      find.byType(LoginPage),
      matchesGoldenFile('goldens/login_light.png'),
    );
  });

  testWidgets('login — dark', (tester) async {
    await pumpScreen(tester, subject(), dark: true);
    await expectLater(
      find.byType(LoginPage),
      matchesGoldenFile('goldens/login_dark.png'),
    );
  });
}
