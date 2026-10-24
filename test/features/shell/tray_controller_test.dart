import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/app/shell/tray_controller.dart';
import 'package:rbnotes/app/shell/tray_host.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../helpers/test_db.dart';

/// Registra as chamadas do `tray_manager` sem tocar na plataforma.
class FakeTrayHost implements TrayHost {
  int iconSets = 0;
  int destroys = 0;
  int menuSets = 0;
  bool listening = false;
  Menu? lastMenu;

  @override
  void addListener(TrayListener listener) => listening = true;

  @override
  void removeListener(TrayListener listener) => listening = false;

  @override
  Future<void> setIcon(String path, {bool isTemplate = false}) async =>
      iconSets++;

  @override
  Future<void> setToolTip(String tooltip) async {}

  @override
  Future<void> setContextMenu(Menu menu) async {
    menuSets++;
    lastMenu = menu;
  }

  @override
  Future<void> popUpContextMenu() async {}

  @override
  Future<void> destroy() async => destroys++;
}

void main() {
  late AppDatabase db;
  late NoteRepository repo;
  late FakeRbNative native;
  late TranscriptionQueue queue;
  late SettingsStore settings;
  late SharedPreferences prefs;
  late AppPaths paths;
  late Directory tmp;
  late RecordingCubit recording;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = memoryDb();
    repo = memoryRepo(db);
    native = FakeRbNative();
    settings = SettingsStore(prefs);
    queue = TranscriptionQueue(
      native: native,
      repository: repo,
      settings: settings,
      vocabulary: VocabularyRepository(db),
    );
    tmp = await Directory.systemTemp.createTemp('rbnotes_tray');
    paths = AppPaths.forTesting(tmp);
    recording = RecordingCubit(
      native: native,
      repository: repo,
      queue: queue,
      settings: settings,
      paths: paths,
      diagnostics: native.diagnostics(),
    );
  });

  tearDown(() async {
    await recording.close();
    await queue.dispose();
    await native.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  TrayController controller(FakeTrayHost host) => TrayController(
    recording: recording,
    onOpen: () async {},
    settings: settings,
    host: host,
  );

  test('init mostra o ícone quando a preferência está ligada', () async {
    await settings.setShowInMenuBar(value: true);
    final host = FakeTrayHost();
    final tray = controller(host);
    await tray.init();
    expect(tray.isVisible, isTrue);
    expect(host.iconSets, 1);
    expect(host.menuSets, 1);
    expect(host.listening, isTrue);
    tray.dispose();
  });

  test('init não mostra o ícone quando a preferência está desligada', () async {
    await settings.setShowInMenuBar(value: false);
    final host = FakeTrayHost();
    final tray = controller(host);
    await tray.init();
    expect(tray.isVisible, isFalse);
    expect(host.iconSets, 0);
    tray.dispose();
  });

  test('setVisible mostra e remove o ícone ao vivo', () async {
    await settings.setShowInMenuBar(value: false);
    final host = FakeTrayHost();
    final tray = controller(host);
    await tray.init();
    expect(tray.isVisible, isFalse);

    await tray.setVisible(enabled: true);
    expect(tray.isVisible, isTrue);
    expect(host.iconSets, 1);

    await tray.setVisible(enabled: false);
    expect(tray.isVisible, isFalse);
    expect(host.destroys, greaterThanOrEqualTo(1));

    tray.dispose();
  });

  test('setVisible é idempotente', () async {
    final host = FakeTrayHost();
    final tray = controller(host);
    await tray.setVisible(enabled: true);
    await tray.setVisible(enabled: true);
    expect(host.iconSets, 1);
    tray.dispose();
  });

  test('o menu só expõe RbNotes e o estado, nunca um título', () async {
    final host = FakeTrayHost();
    final tray = controller(host);
    await tray.setVisible(enabled: true);
    final labels = host.lastMenu!.items!.map((i) => i.label).toList();
    expect(labels, contains('Gravar'));
    expect(labels, contains('Ocioso'));
    expect(labels, contains('Abrir RbNotes'));
    tray.dispose();
  });
}
