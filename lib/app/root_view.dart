import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/app/shell/app_shell.dart';
import 'package:rbnotes/app/shell/shell_overlay_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/features/ai/presentation/ask_cubit.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/auth/presentation/login_cubit.dart';
import 'package:rbnotes/features/auth/presentation/login_page.dart';
import 'package:rbnotes/features/auth/presentation/session_cubit.dart';
import 'package:rbnotes/features/diary/presentation/diary_cubit.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:rbnotes/features/onboarding/presentation/onboarding_page.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:rbnotes/notifications/notification_service.dart';

/// Decide a tela de topo (login → onboarding → app) e injeta os cubits de cada
/// uma. `SessionCubit` e `RecordingCubit` vêm de cima (`RbNotesApp`).
class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, AppScreen>(
      builder: (context, screen) {
        return switch (screen) {
          AppScreen.login => BlocProvider(
            create: (_) => LoginCubit(di<AuthService>()),
            child: const LoginPage(),
          ),
          AppScreen.onboarding => BlocProvider(
            create: (_) => OnboardingCubit(
              native: di(),
              settings: di(),
              requestNotifications: di<NotificationService>().requestPermission,
            ),
            child: _Onboarding(),
          ),
          AppScreen.app => MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) => LibraryCubit(
                  notes: di(),
                  noteAi: di(),
                  library: di(),
                ),
              ),
              BlocProvider(
                create: (_) => NoteViewCubit(
                  notes: di(),
                  noteAi: di(),
                  ai: di(),
                  native: di(),
                  player: di(),
                  audioSync: di.isRegistered<AudioSync>()
                      ? di<AudioSync>()
                      : null,
                  paths: di(),
                ),
              ),
              BlocProvider(
                create: (_) => AskCubit(ai: di(), notes: di(), noteAi: di()),
              ),
              BlocProvider(create: (_) => ShellOverlayCubit()),
              BlocProvider(
                create: (_) => DiaryCubit(
                  diary: di(),
                  notes: di(),
                  noteAi: di(),
                  ai: di(),
                  settings: di(),
                  authenticate: di<NotificationService>().authenticateBiometric,
                ),
              ),
            ],
            child: const AppShell(),
          ),
        };
      },
    );
  }
}

class _Onboarding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionCubit>();
    final user = di<AuthService>().currentUser;
    final firstName = (user?.name ?? 'Você').split(' ').first;
    return OnboardingPage(
      firstName: firstName,
      onFinish: session.completeOnboarding,
      onRecordFirst: () {
        unawaited(session.completeOnboarding());
        unawaited(Future<void>.microtask(() => di<RecordingCubit>().start()));
      },
    );
  }
}
