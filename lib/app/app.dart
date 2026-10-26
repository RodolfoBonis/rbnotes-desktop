import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rbnotes/app/accent_cubit.dart';
import 'package:rbnotes/app/root_view.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/diagnostics_monitor.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/core/windowing/main_window.dart';
import 'package:rbnotes/features/auth/presentation/session_cubit.dart';
import 'package:rbnotes/features/diary/presentation/diary_gate.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/security/presentation/lock_screen.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class RbNotesApp extends StatelessWidget {
  const RbNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // Shared with the Settings window (same isolate), so theme/accent and
        // the Touch ID lock apply live across both windows.
        BlocProvider.value(value: di<ThemeModeCubit>()),
        BlocProvider.value(value: di<AccentCubit>()),
        BlocProvider.value(value: di<AppLockCubit>()),
        BlocProvider(
          create: (_) => SessionCubit(auth: di(), prefs: di()),
        ),
        BlocProvider(create: (_) => DiaryGate(auth: di())),
        BlocProvider(
          create: (context) => RecordingCubit(
            native: di(),
            repository: di(),
            queue: di(),
            settings: di(),
            paths: di(),
            diagnostics: di<DiagnosticsMonitor>().stream,
            aiActivity: di(),
            enrichment: di(),
            // Overlay do notch: usa-o quando a gravação começa com o app sem
            // foco; traz a janela ao foco na ação "openApp" do overlay.
            isForeground: () async => di<MainWindowHandle>().isActive,
            onOpenApp: () async => di<MainWindowHandle>().activate(),
            // Travado: o overlay esconde a transcrição ao vivo.
            isLocked: () => context.read<AppLockCubit>().state.locked,
          ),
        ),
      ],
      child: BlocBuilder<ThemeModeCubit, ThemeMode>(
        builder: (context, mode) => BlocBuilder<AccentCubit, Color>(
          builder: (context, accent) => MaterialApp(
            title: 'RbNotes',
            debugShowCheckedModeBanner: false,
            theme: RbNotesTheme.light(accent),
            darkTheme: RbNotesTheme.dark(accent),
            themeMode: mode,
            locale: const Locale('pt', 'BR'),
            supportedLocales: const [Locale('pt', 'BR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const RootView(),
            builder: (context, child) => SentryWidget(
              child: BlocBuilder<AppLockCubit, AppLockState>(
                builder: (context, lock) => Stack(
                  children: [
                    // Sob a LockScreen o conteúdo não recebe foco (C1): nenhum
                    // atalho/campo age enquanto o app está travado.
                    ExcludeFocus(excluding: lock.locked, child: child!),
                    if (lock.locked) const LockScreen(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
