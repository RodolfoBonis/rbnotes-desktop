import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/native/fake_rb_native.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/fake_audio_sync.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late NoteAiRepository noteAi;
  late FakeRbNative native;
  late FakeAudioPlayer player;
  late FakeAudioSync audio;
  late AppPaths paths;
  late Directory tmp;

  setUp(() async {
    db = memoryDb();
    notes = NoteRepository(db);
    noteAi = NoteAiRepository(db);
    native = FakeRbNative();
    player = FakeAudioPlayer();
    audio = FakeAudioSync();
    tmp = await Directory.systemTemp.createTemp('note_audio');
    paths = AppPaths.forTesting(tmp);
    await Directory(paths.audioCacheDir).create(recursive: true);
  });

  tearDown(() async {
    await native.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  // Nota vinda de outro Mac: sem áudio local (playbackPath null), mas com
  // duração conhecida.
  Future<void> seedRemoteNote(String id) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: id,
          createdAt: DateTime(2026, 6),
          updatedAt: DateTime(2026, 6),
          durationMs: const Value(5000),
          status: NoteStatus.ready,
          source: NoteSource.recording,
        ),
      );

  NoteViewCubit build() => NoteViewCubit(
    notes: notes,
    noteAi: noteAi,
    ai: FakeAiClient(stepDelay: Duration.zero, thinkDelay: Duration.zero),
    native: native,
    player: player,
    audioSync: audio,
    paths: paths,
  );

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('baixa o áudio sob demanda e toca a partir do cache', () async {
    await seedRemoteNote('n1');
    audio.downloadBody = Uint8List.fromList(List<int>.filled(64, 9));
    final cubit = build();

    await cubit.load('n1');
    await settle();

    final cachePath = p.join(paths.audioCacheDir, 'n1.m4a');
    expect(File(cachePath).existsSync(), isTrue, reason: 'gravou no cache');
    expect(player.loaded, isNotNull, reason: 'carregou o player do cache');
    expect(cubit.state.audioDownloadProgress, isNull, reason: 'progresso some');
    await cubit.close();
  });

  test('reporta progresso durante o download', () async {
    await seedRemoteNote('n1');
    audio.downloadBody = Uint8List.fromList(List<int>.filled(100, 1));
    final cubit = build();
    final seen = <double?>[];
    final sub = cubit.stream.listen((s) => seen.add(s.audioDownloadProgress));

    await cubit.load('n1');
    await settle();

    expect(seen.any((v) => v != null && v > 0 && v < 1), isTrue);
    await sub.cancel();
    await cubit.close();
  });

  test('usa o cache já baixado (offline) sem baixar de novo', () async {
    await seedRemoteNote('n1');
    final cachePath = p.join(paths.audioCacheDir, 'n1.m4a');
    await File(cachePath).writeAsBytes([1, 2, 3]);
    audio.downloadBody = null; // se tentar baixar, daria 404
    final cubit = build();

    await cubit.load('n1');
    await settle();

    expect(player.loaded, isNotNull);
    await cubit.close();
  });

  test('404 → aviso "áudio não disponível" e nada toca', () async {
    await seedRemoteNote('n1');
    audio.downloadBody = null; // simula 404
    final cubit = build();
    final notices = <String>[];
    final sub = cubit.notices.listen(notices.add);

    await cubit.load('n1');
    await settle();

    expect(notices, contains('Áudio não disponível.'));
    expect(player.loaded, isNull);
    final cachePath = p.join(paths.audioCacheDir, 'n1.m4a');
    expect(File(cachePath).existsSync(), isFalse, reason: 'sem parcial');
    await sub.cancel();
    await cubit.close();
  });
}
