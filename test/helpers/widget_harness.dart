import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/core/theme/rbnotes_theme.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_audio_player.dart';
import 'test_db.dart';

/// Monta um ambiente de DI em memória para os widget tests.
class WidgetHarness {
  WidgetHarness._(
    this.db,
    this.native,
    this.repo,
    this.queue,
    this.settings,
    this.prefs,
    this.paths,
    this.tmp,
  );

  final AppDatabase db;
  final FakeRbNative native;
  final NoteRepository repo;
  final TranscriptionQueue queue;
  final SettingsStore settings;
  final SharedPreferences prefs;
  final AppPaths paths;
  final Directory tmp;

  static Future<WidgetHarness> create() async {
    if (di.isRegistered<AppDatabase>()) await di.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = memoryDb();
    final native = FakeRbNative();
    final repo = memoryRepo(db);
    final settings = SettingsStore(prefs);
    final queue = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
    );
    final dictation = DictationService(
      native: native,
      repository: repo,
      settings: settings,
    );
    final tmp = await Directory.systemTemp.createTemp('rbnotes_widget');

    di
      ..registerSingleton<SharedPreferences>(prefs)
      ..registerSingleton<AppDatabase>(db)
      ..registerSingleton<RbNative>(native)
      ..registerSingleton<SettingsStore>(settings)
      ..registerSingleton<NoteRepository>(repo)
      ..registerSingleton<TranscriptionQueue>(queue)
      ..registerSingleton<DictationService>(dictation)
      ..registerFactory<AudioPlayerController>(FakeAudioPlayer.new);

    return WidgetHarness._(
      db,
      native,
      repo,
      queue,
      settings,
      prefs,
      AppPaths.forTesting(tmp),
      tmp,
    );
  }

  Widget wrap(Widget child) => MaterialApp(
    theme: RbNotesTheme.light,
    home: Scaffold(body: child),
  );

  Future<void> dispose() async {
    await queue.dispose();
    await native.dispose();
    await db.close();
    await di.reset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}
