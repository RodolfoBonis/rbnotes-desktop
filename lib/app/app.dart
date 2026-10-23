import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rbnotes/app/root_view.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/diagnostics_monitor.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/auth/presentation/session_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class RbNotesApp extends StatelessWidget {
  const RbNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeModeCubit(di())),
        BlocProvider(
          create: (_) => SessionCubit(auth: di(), prefs: di()),
        ),
        BlocProvider(
          create: (_) => RecordingCubit(
            native: di(),
            repository: di(),
            queue: di(),
            settings: di(),
            paths: di(),
            diagnostics: di<DiagnosticsMonitor>().stream,
            aiActivity: di(),
            enrichment: di(),
          ),
        ),
      ],
      child: BlocBuilder<ThemeModeCubit, ThemeMode>(
        builder: (context, mode) => MaterialApp(
          title: 'RbNotes',
          debugShowCheckedModeBanner: false,
          theme: RbNotesTheme.light,
          darkTheme: RbNotesTheme.dark,
          themeMode: mode,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const RootView(),
          builder: (context, child) => SentryWidget(child: child!),
        ),
      ),
    );
  }
}
