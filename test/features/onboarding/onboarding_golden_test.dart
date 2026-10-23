import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:rbnotes/features/onboarding/presentation/onboarding_page.dart';

import '../../helpers/golden.dart';

class _MockOnboardingCubit extends MockCubit<OnboardingState>
    implements OnboardingCubit {}

void main() {
  Widget subject(OnboardingState state) {
    final cubit = _MockOnboardingCubit();
    whenListen(
      cubit,
      const Stream<OnboardingState>.empty(),
      initialState: state,
    );
    return BlocProvider<OnboardingCubit>.value(
      value: cubit,
      child: const OnboardingPage(
        firstName: 'Renata',
        onFinish: _noop,
        onRecordFirst: _noop,
      ),
    );
  }

  const grantedAll = {
    OnbPerm.mic: PermState.ok,
    OnbPerm.screen: PermState.ok,
    OnbPerm.ax: PermState.ok,
    OnbPerm.notif: PermState.ok,
  };

  for (final (step, state) in <(int, OnboardingState)>[
    (0, const OnboardingState()),
    (1, const OnboardingState(step: 1)),
    (2, const OnboardingState(step: 2, permissions: grantedAll)),
    (3, const OnboardingState(step: 3, permissions: grantedAll)),
  ]) {
    testWidgets('onboarding — passo $step', (tester) async {
      await pumpScreen(tester, subject(state));
      await expectLater(
        find.byType(OnboardingPage),
        matchesGoldenFile('goldens/onboarding_$step.png'),
      );
    });
  }
}

void _noop() {}
