import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:rbnotes/core/config/app_config.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/app_bloc_observer.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/observability/diagnostics_monitor.dart';
import 'package:rbnotes/core/observability/file_log_sink.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/core/windowing/app_windows.dart';
import 'package:rbnotes/core/windowing/settings_window_manager.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/recording/data/meeting_detection_service.dart';
import 'package:rbnotes/features/recording/data/record_note_hotkey_service.dart';
import 'package:rbnotes/features/settings/data/retention_service.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';
import 'package:rbnotes/features/settings/presentation/settings_window.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/sync/data/sync_trigger.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> bootstrap(
  Widget Function() builder, {
  required Flavor flavor,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.forFlavor(flavor);

  // Observabilidade em release: log em arquivo rotativo
  // (~/Library/Logs/RbNotes/rbnotes.log). O Sentry segue opcional (só com DSN).
  AppLogger.attachFileSink(
    await FileLogSink.open(Directory(AppPaths.logsDirPath)),
  );
  AppLogger.info(
    'app boot',
    data: {'env': config.environment},
  );

  // Inter vem empacotada em assets/fonts — sem download em runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');

  // A janela principal é criada pela API de windowing do Flutter (ver
  // core/windowing/app_windows.dart), não mais pelo window_manager: no macOS
  // a engine roda headless/multi-view para suportar múltiplas janelas.

  await configureDependencies(config);
  // Owns the single Settings window (opened on ⌘, / focused if already open).
  di.registerSingleton<SettingsWindowManager>(
    SettingsWindowManager(
      createWindow: createSettingsNativeWindow,
      resolveInitialTitle: () => settingsTabTitle(SettingsTab.geral),
    ),
  );
  Bloc.observer = const AppBlocObserver();
  // Ditado global: registra o atalho e escuta os eventos do plugin.
  unawaited(di<DictationService>().start());
  // Atalho global "Gravar nota": registra o atalho e escuta os pressionamentos
  // (o shell liga o disparo ao RecordingCubit).
  unawaited(di<RecordNoteHotkeyService>().start());
  // Detecção de reunião: liga/desliga conforme "Sugerir gravação ao detectar
  // reunião" (o shell consome as sugestões e mostra o prompt/notificação).
  unawaited(di<MeetingDetectionService>().applySettings());
  // Retoma transcrições presas em `transcribing` de uma sessão anterior.
  unawaited(di<TranscriptionQueue>().requeueInterrupted());
  // Recupera (uma vez) as notas que falharam pelo bug de migração: `failed`
  // com áudio em disco e 0 segmentos voltam para a fila.
  unawaited(
    di<TranscriptionQueue>().recoverFailedNotes(di<SharedPreferences>()),
  );
  // Nunca deixa um "Resumo em preparação…" sem job: re-enriquece pendentes.
  unawaited(di<EnrichmentService>().requeuePending());
  // Aplica retenção e "apagar áudio após transcrever" (boot + a cada 24h).
  di<RetentionService>().start();
  // Diagnósticos assíncronos do nativo → Sentry com contexto.
  di<DiagnosticsMonitor>().start();
  // Sync real (quando o backend está ligado): dispara ao abrir + a cada 2 min,
  // e retoma uploads de áudio pendentes.
  if (di.isRegistered<SyncService>()) di<SyncService>().start();
  // Dispara sync (debounced) em qualquer mutação local relevante, sem depender
  // só da cadência de 2 min.
  if (di.isRegistered<SyncTrigger>()) di<SyncTrigger>().start();
  if (di.isRegistered<AudioUploadQueue>()) {
    unawaited(di<AudioUploadQueue>().process());
  }

  Future<void> run() async => runRbNotesWindows(
    mainApp: builder(),
    settingsManager: di<SettingsWindowManager>(),
    settingsBuilder: (_) => const SettingsWindowApp(),
  );

  // Erros de build/render (ex.: um diálogo que quebra) também vão para o log
  // em arquivo: em release o Flutter só desenha uma caixa cinza no lugar.
  void logFlutterError(FlutterErrorDetails details) {
    unawaited(
      AppLogger.error(
        details.exception,
        details.stack,
        reason: details.context?.toDescription() ?? 'flutter_error',
        category: 'flutter',
      ),
    );
  }

  if (!config.hasSentry) {
    FlutterError.onError = (details) {
      logFlutterError(details);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      logFlutterError(FlutterErrorDetails(exception: error, stack: stack));
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
