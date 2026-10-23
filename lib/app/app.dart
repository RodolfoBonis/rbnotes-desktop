import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/routing/app_router.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/features/notes/presentation/notes_list_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class RbNotesApp extends StatefulWidget {
  const RbNotesApp({super.key});

  @override
  State<RbNotesApp> createState() => _RbNotesAppState();
}

class _RbNotesAppState extends State<RbNotesApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildRouter();
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeModeCubit(di())),
        BlocProvider(
          create: (_) => RecordingCubit(
            native: di(),
            repository: di(),
            queue: di(),
            settings: di(),
            paths: di(),
          ),
        ),
        BlocProvider(
          create: (_) => NotesListCubit(repository: di(), queue: di()),
        ),
      ],
      child: BlocBuilder<ThemeModeCubit, ThemeMode>(
        builder: (context, mode) => MaterialApp.router(
          title: 'RbNotes',
          debugShowCheckedModeBanner: false,
          theme: RbNotesTheme.light,
          darkTheme: RbNotesTheme.dark,
          themeMode: mode,
          routerConfig: _router,
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => SentryWidget(child: child!),
        ),
      ),
    );
  }
}
