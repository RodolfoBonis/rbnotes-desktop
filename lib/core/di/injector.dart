import 'dart:async';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:rbnotes/core/auth/oidc_client.dart';
import 'package:rbnotes/core/auth/token_store.dart';
import 'package:rbnotes/core/config/app_config.dart';
import 'package:rbnotes/core/network/api_client.dart';
import 'package:rbnotes/core/network/session_events.dart';
import 'package:rbnotes/core/observability/diagnostics_monitor.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/ai_usage_client.dart';
import 'package:rbnotes/features/ai/data/api_ai_client.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/ai/data/fake_ai_usage_client.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/auth/data/keycloak_auth_service.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/library/data/demo_seeder.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:rbnotes/features/notes/presentation/just_audio_player.dart';
import 'package:rbnotes/features/recording/data/meeting_detection_service.dart';
import 'package:rbnotes/features/recording/data/record_note_hotkey_service.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';
import 'package:rbnotes/features/settings/data/retention_service.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/sync/data/api_sync_client.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:rbnotes/features/sync/data/audio_upload_coordinator.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_crypto.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/sync/data/sync_trigger.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:rbnotes/notifications/notification_coordinator.dart';
import 'package:rbnotes/notifications/notification_scheduler.dart';
import 'package:rbnotes/notifications/notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

final GetIt di = GetIt.instance;

/// Raiz de composição. Serviços e repositórios são registrados pela interface
/// para os testes poderem substituí-los.
///
/// Em `development` (ou `--dart-define=RBNOTES_USE_BACKEND=false`) usa os fakes
/// locais de Auth/Sync/IA; com `useBackend` injeta o Keycloak + a `rbnotes-api`.
Future<void> configureDependencies(AppConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  final paths = await AppPaths.resolve();
  final database = AppDatabase();

  // ---- Plugin nativo real (macOS). Testes injetam FakeRbNative. ----
  final RbNative native = MethodChannelRbNative();

  final noteKeyStore = SecureNoteKeyStore();
  final syncCrypto = SyncCrypto(noteKeyStore);

  final settings = SettingsStore(prefs);
  final repository = NoteRepository(database);
  final noteAi = NoteAiRepository(database);
  final library = LibraryRepository(database);
  final diary = DiaryRepository(database);
  final vocabulary = VocabularyRepository(database);
  final queue = TranscriptionQueue(
    native: native,
    repository: repository,
    settings: settings,
    vocabulary: vocabulary,
    paths: paths,
  );
  final dictation = DictationService(
    native: native,
    repository: repository,
    settings: settings,
    vocabulary: vocabulary,
  );
  final recordNoteHotkey = RecordNoteHotkeyService(
    native: native,
    settings: settings,
  );
  final meetingDetection = MeetingDetectionService(
    native: native,
    settings: settings,
  );
  final diagnostics = DiagnosticsMonitor(native);
  final notifier = LocalNotifier();
  final notificationScheduler = NotificationScheduler(
    notifier: notifier,
    settings: settings,
  );
  final aiActivity = AiActivity();

  // ---- IA / sync / auth: fakes locais ou clientes reais. ----
  final AiClient ai;
  final AiUsageClient aiUsage;
  final SyncClient sync;
  final AuthService auth;
  ApiClient? apiClient;
  SessionEvents? sessionEvents;
  SyncService? syncService;
  SyncTrigger? syncTrigger;
  AudioSync? audioSync;
  AudioUploadQueue? audioQueue;
  AudioUploadCoordinator? audioCoordinator;

  if (config.useBackend) {
    final tokenStore = SecureTokenStore();
    final events = SessionEvents();
    sessionEvents = events;
    final oidc = OidcClient(
      dio: Dio(),
      issuer: config.authIssuer,
      clientId: config.authClientId,
      redirectUri: config.authRedirectUri,
    );
    final api = ApiClient(
      baseUrl: config.apiBaseUrl,
      tokens: tokenStore,
      oidc: oidc,
      events: events,
    );
    apiClient = api;
    final keycloak = KeycloakAuthService(
      oidc: oidc,
      tokens: tokenStore,
      api: api,
      events: events,
    );
    auth = keycloak;
    ai = ApiAiClient(
      api,
      activity: aiActivity,
      modelName: () => settings.aiModel,
    );
    aiUsage = ApiAiUsageClient(api);
    final syncClient = ApiSyncClient(api);
    sync = syncClient;
    syncService = SyncService(
      client: syncClient,
      store: SyncLocalStore(database, crypto: syncCrypto),
      settings: settings,
      prefs: prefs,
    );
    audioSync = AudioSync(api);
    audioQueue = AudioUploadQueue(
      audio: audioSync,
      settings: settings,
      prefs: prefs,
      notes: repository,
    );
    audioCoordinator = AudioUploadCoordinator(
      queue: audioQueue,
      notes: repository,
      settings: settings,
    )..attachTo(queue);
    syncTrigger = SyncTrigger(db: database, sync: syncService);
    await keycloak.restore();
  } else {
    ai = FakeAiClient();
    aiUsage = const FakeAiUsageClient();
    sync = const FakeSyncClient();
    auth = FakeAuthService();
  }

  final notificationCoordinator = NotificationCoordinator(
    notifier: notifier,
    scheduler: notificationScheduler,
    noteAi: noteAi,
    ai: ai,
    settings: settings,
  );

  final enrichment = EnrichmentService(
    ai: ai,
    notes: repository,
    noteAi: noteAi,
    onNoteReady: ({required noteId, required title, required failed}) {
      unawaited(() async {
        final focused = await windowManager.isFocused();
        await notificationScheduler.notifyNoteReady(
          noteId: noteId,
          title: title,
          windowFocused: focused,
          failed: failed,
        );
      }());
    },
    vocabulary: vocabulary,
    settings: settings,
  )..attachTo(queue);

  // Retenção conhece a fila de upload (quando há backend) para subir o áudio
  // antes de apagá-lo com "apagar áudio após transcrever".
  final retention = RetentionService(
    settings: settings,
    notes: repository,
    audioQueue: audioQueue,
  );

  di
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<AppPaths>(paths)
    ..registerSingleton<AppDatabase>(database)
    ..registerSingleton<RbNative>(native)
    ..registerSingleton<SettingsStore>(settings)
    ..registerSingleton<NoteRepository>(repository)
    ..registerSingleton<NoteAiRepository>(noteAi)
    ..registerSingleton<LibraryRepository>(library)
    ..registerSingleton<DiaryRepository>(diary)
    ..registerSingleton<VocabularyRepository>(vocabulary)
    ..registerSingleton<RetentionService>(retention)
    ..registerSingleton<TranscriptionQueue>(queue)
    ..registerSingleton<DictationService>(dictation)
    ..registerSingleton<RecordNoteHotkeyService>(recordNoteHotkey)
    ..registerSingleton<MeetingDetectionService>(meetingDetection)
    ..registerSingleton<DiagnosticsMonitor>(diagnostics)
    ..registerSingleton<AiActivity>(aiActivity)
    ..registerSingleton<AiClient>(ai)
    ..registerSingleton<AiUsageClient>(aiUsage)
    ..registerSingleton<SyncClient>(sync)
    ..registerSingleton<NoteKeyStore>(noteKeyStore)
    ..registerSingleton<BiometricAuth>(LocalBiometricAuth())
    ..registerSingleton<SyncCrypto>(syncCrypto)
    ..registerSingleton<AuthService>(auth)
    ..registerSingleton<Notifier>(notifier)
    ..registerSingleton<NotificationScheduler>(notificationScheduler)
    ..registerSingleton<NotificationCoordinator>(notificationCoordinator)
    ..registerSingleton<EnrichmentService>(enrichment)
    ..registerFactory<AudioPlayerController>(JustAudioPlayer.new);

  if (sessionEvents != null) di.registerSingleton<SessionEvents>(sessionEvents);
  if (apiClient != null) di.registerSingleton<ApiClient>(apiClient);
  if (syncService != null) di.registerSingleton<SyncService>(syncService);
  if (syncTrigger != null) di.registerSingleton<SyncTrigger>(syncTrigger);
  if (audioSync != null) di.registerSingleton<AudioSync>(audioSync);
  if (audioQueue != null) di.registerSingleton<AudioUploadQueue>(audioQueue);
  if (audioCoordinator != null) {
    di.registerSingleton<AudioUploadCoordinator>(audioCoordinator);
  }

  // Dados de demonstração: só no flavor development ou com RBNOTES_DEMO=true.
  // Em produção, ao contrário, limpamos as notas de seed que vazaram para a
  // máquina do dono (apenas as que ele não editou).
  final seeder = DemoSeeder(
    notes: repository,
    noteAi: noteAi,
    library: library,
    diary: diary,
    // Em produção o purge usa o sync para mandar tombstones do seed vazado.
    sync: config.demoSeed ? null : sync,
  );
  if (config.demoSeed) {
    await seeder.seedIfEmpty();
  } else {
    await library.ensureBuiltinCollections();
    await seeder.purgeSeedNotes();
  }

  unawaited(notifier.init());
  unawaited(notificationCoordinator.start());
}
