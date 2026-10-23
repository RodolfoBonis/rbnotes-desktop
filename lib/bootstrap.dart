import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:rbnotes/core/config/app_config.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/app_bloc_observer.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:window_manager/window_manager.dart';

Future<void> bootstrap(
  Widget Function() builder, {
  required Flavor flavor,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.forFlavor(flavor);

  // Inter vem empacotada em assets/fonts — sem download em runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'RbNotes',
      size: Size(1180, 820),
      minimumSize: Size(960, 640),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  await configureDependencies(config);
  Bloc.observer = const AppBlocObserver();
  // Ditado global: registra o atalho e escuta os eventos do plugin.
  unawaited(di<DictationService>().start());

  Future<void> run() async => runApp(builder());

  if (!config.hasSentry) {
    FlutterError.onError = FlutterError.presentError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FlutterError.presentError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
      return true;
    };
    await run();
    return;
  }

  await SentryFlutter.init(
    (o) => o
      ..dsn = config.sentryDsn
      ..environment = config.environment
      ..tracesSampleRate = kReleaseMode ? 0.2 : 1.0
      ..sendDefaultPii = false
      ..attachScreenshot = false,
    appRunner: run,
  );
}
