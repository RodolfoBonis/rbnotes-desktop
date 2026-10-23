import 'package:get_it/get_it.dart';
import 'package:rbnotes/core/config/app_config.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:rbnotes/features/notes/presentation/just_audio_player.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GetIt di = GetIt.instance;

/// Raiz de composição. Serviços e repositórios são registrados pela interface
/// para os testes poderem substituí-los.
///
/// O plugin real (`MethodChannelRbNative`) é injetado como `RbNative`; os
/// testes substituem por um fake. Nenhuma feature conhece a implementação.
Future<void> configureDependencies(AppConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  final paths = await AppPaths.resolve();
  final database = AppDatabase();

  // ---- Plugin nativo real (macOS). Testes injetam FakeRbNative. ----
  final RbNative native = MethodChannelRbNative();

  final settings = SettingsStore(prefs);
  final repository = NoteRepository(database);
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

  di
    ..registerSingleton<AppConfig>(config)
    ..registerSingleton<SharedPreferences>(prefs)
    ..registerSingleton<AppPaths>(paths)
    ..registerSingleton<AppDatabase>(database)
    ..registerSingleton<RbNative>(native)
    ..registerSingleton<SettingsStore>(settings)
    ..registerSingleton<NoteRepository>(repository)
    ..registerSingleton<TranscriptionQueue>(queue)
    ..registerSingleton<DictationService>(dictation)
    ..registerFactory<AudioPlayerController>(JustAudioPlayer.new);
}
