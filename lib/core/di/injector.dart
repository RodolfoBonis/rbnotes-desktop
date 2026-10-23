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
import 'package:rbnotes/features/ai/data/api_ai_client.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
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
import 'package:rbnotes/features/settings/data/retention_service.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/sync/data/api_sync_client.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:rbnotes/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final settings = SettingsStore(prefs);
  final repository = NoteRepository(database);
  final noteAi = NoteAiRepository(database);
  final library = LibraryRepository(database);
  final diary = DiaryRepository(database);
  final vocabulary = VocabularyRepository(database);
  final retention = RetentionService(settings: settings, notes: repository);
  final queue = TranscriptionQueue(
    native: native,
    repository: repository,
    settings: settings,
    vocabulary: vocabulary,
  );
  final dictation = DictationService(
    native: native,
    repository: repository,
    settings: settings,
    vocabulary: vocabulary,
  );
  final diagnostics = DiagnosticsMonitor(native);
  final notifications = NotificationService();
  final aiActivity = AiActivity();

  // ---- IA / sync / auth: fakes locais ou clientes reais. ----
  final AiClient ai;
  final SyncClient sync;
  final AuthService auth;
  ApiClient? apiClient;
  SessionEvents? sessionEvents;
  SyncService? syncService;
  AudioSync? audioSync;
  AudioUploadQueue? audioQueue;

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
    final syncClient = ApiSyncClient(api);
    sync = syncClient;
    syncService = SyncService(
      client: syncClient,
      store: SyncLocalStore(database),
      settings: settings,
      prefs: prefs,
    );
    audioSync = AudioSync(api);
    audioQueue = AudioUploadQueue(
      audio: audioSync,
      settings: settings,
      prefs: prefs,
    );
    await keycloak.restore();
  } else {
    ai = FakeAiClient();
    sync = const FakeSyncClient();
    auth = FakeAuthService();
  }

  final enrichment = EnrichmentService(
    ai: ai,
    notes: repository,
    noteAi: noteAi,
    vocabulary: vocabulary,
    settings: settings,
  )..attachTo(queue);

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
    ..registerSingleton<DiagnosticsMonitor>(diagnostics)
    ..registerSingleton<AiActivity>(aiActivity)
    ..registerSingleton<AiClient>(ai)
    ..registerSingleton<SyncClient>(sync)
    ..registerSingleton<AuthService>(auth)
    ..registerSingleton<NotificationService>(notifications)
    ..registerSingleton<EnrichmentService>(enrichment)
    ..registerFactory<AudioPlayerController>(JustAudioPlayer.new);

  if (sessionEvents != null) di.registerSingleton<SessionEvents>(sessionEvents);
  if (apiClient != null) di.registerSingleton<ApiClient>(apiClient);
  if (syncService != null) di.registerSingleton<SyncService>(syncService);
  if (audioSync != null) di.registerSingleton<AudioSync>(audioSync);
  if (audioQueue != null) di.registerSingleton<AudioUploadQueue>(audioQueue);

  // Semeia os dados do design na primeira execução (só local-first; com backend
  // as notas reais chegam pelo sync).
  if (!config.useBackend) {
    await DemoSeeder(
      notes: repository,
      noteAi: noteAi,
      library: library,
      diary: diary,
    ).seedIfEmpty();
  }

  unawaited(notifications.init());
}
