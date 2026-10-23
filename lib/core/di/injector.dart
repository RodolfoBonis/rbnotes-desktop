import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:rbnotes/core/config/app_config.dart';
import 'package:rbnotes/core/observability/diagnostics_monitor.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_client.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/library/data/demo_seeder.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:rbnotes/features/notes/presentation/just_audio_player.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:rbnotes/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GetIt di = GetIt.instance;

/// Raiz de composição. Serviços e repositórios são registrados pela interface
/// para os testes poderem substituí-los.
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
  final queue = TranscriptionQueue(
    native: native,
    repository: repository,
    settings: settings,
  );
  final dictation = DictationService(
    native: native,
    repository: repository,
    settings: settings,
  );
  final diagnostics = DiagnosticsMonitor(native);

  // ---- IA / sync / auth (local-first via fakes; real vem na integração) ----
  final AiClient ai = FakeAiClient();
  const SyncClient sync = FakeSyncClient();
  final AuthService auth = FakeAuthService();
  final notifications = NotificationService();

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
    ..registerSingleton<TranscriptionQueue>(queue)
    ..registerSingleton<DictationService>(dictation)
    ..registerSingleton<DiagnosticsMonitor>(diagnostics)
    ..registerSingleton<AiClient>(ai)
    ..registerSingleton<SyncClient>(sync)
    ..registerSingleton<AuthService>(auth)
    ..registerSingleton<NotificationService>(notifications)
    ..registerSingleton<EnrichmentService>(enrichment)
    ..registerFactory<AudioPlayerController>(JustAudioPlayer.new);

  // Semeia os dados do design na primeira execução (notas, resumos, diário).
  await DemoSeeder(
    notes: repository,
    noteAi: noteAi,
    library: library,
    diary: diary,
  ).seedIfEmpty();

  unawaited(notifications.init());
}
