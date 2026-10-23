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
import 'package:rbnotes/core/observability/diagnostics_monitor.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/settings/data/retention_service.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
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
      size: Size(1280, 800),
      minimumSize: Size(1040, 680),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    () async {
      // Esconde os botões nativos: o app desenha os próprios traffic lights
      // (ver TrafficLights), posicionados como no design.
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.show();
      await windowManager.focus();
    },
  );

  await configureDependencies(config);
  Bloc.observer = const AppBlocObserver();
  // Ditado global: registra o atalho e escuta os eventos do plugin.
  unawaited(di<DictationService>().start());
  // Retoma transcrições presas em `transcribing` de uma sessão anterior.
  unawaited(di<TranscriptionQueue>().requeueInterrupted());
  // Aplica retenção e "apagar áudio após transcrever" (boot + a cada 24h).
  di<RetentionService>().start();
  // Diagnósticos assíncronos do nativo → Sentry com contexto.
  di<DiagnosticsMonitor>().start();
  // Sync real (quando o backend está ligado): dispara ao abrir + a cada 2 min,
  // e retoma uploads de áudio pendentes.
  if (di.isRegistered<SyncService>()) di<SyncService>().start();
  if (di.isRegistered<AudioUploadQueue>()) {
    unawaited(di<AudioUploadQueue>().process());
  }

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
