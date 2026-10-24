import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/fake_ai_client.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/data/silence_store.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/native/fake_rb_native.dart';
import 'package:rbnotes/native/rb_native.dart';

import '../../helpers/fake_audio_player.dart';
import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late FakeRbNative native;
  late FakeAudioPlayer player;
  late AppPaths paths;
  late Directory tmp;

  setUp(() async {
    db = memoryDb();
    notes = NoteRepository(db);
    native = FakeRbNative();
    player = FakeAudioPlayer();
    tmp = await Directory.systemTemp.createTemp('silence_play');
    paths = AppPaths.forTesting(tmp);
    await Directory(paths.recordingsDir).create(recursive: true);
    await Directory(paths.audioCacheDir).create(recursive: true);
  });

  tearDown(() async {
    await native.dispose();
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  NoteViewCubit build() => NoteViewCubit(
    notes: notes,
    noteAi: NoteAiRepository(db),
    ai: FakeAiClient(stepDelay: Duration.zero, thinkDelay: Duration.zero),
    native: native,
    player: player,
    paths: paths,
  );

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> seed(String id) async {
    final audio = File('${paths.recordingsDir}/$id.m4a')
      ..writeAsStringSync('a');
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            createdAt: DateTime(2026, 6),
            updatedAt: DateTime(2026, 6),
            durationMs: const Value(10000),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            playbackPath: Value(audio.path),
          ),
        );
  }

  test('store salva e lê os intervalos (roundtrip)', () async {
    final store = SilenceStore(paths);
    await store.save('n1', const [
      SilenceRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 4),
      ),
    ]);
    expect(await store.load('n1'), [(2000, 4000)]);
    // Salvar vazio remove o sidecar.
    await store.save('n1', const []);
    expect(await store.load('n1'), isEmpty);
  });

  test('player pula o silêncio com seek automático', () async {
    await seed('n1');
    await SilenceStore(paths).save('n1', const [
      SilenceRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 4),
      ),
    ]);
    final cubit = build();
    await cubit.load('n1');
    await settle();

    expect(cubit.state.silences, [(2000, 4000)]);
    // Posição entra no silêncio → seek automático para o fim.
    player.emitPosition(const Duration(milliseconds: 2500));
    await settle();
    expect(player.seeks, contains(const Duration(milliseconds: 4000)));

    await cubit.close();
  });

  test('duração e posição exibidas descontam o silêncio', () async {
    await seed('n1');
    await SilenceStore(paths).save('n1', const [
      SilenceRange(
        start: Duration(seconds: 2),
        end: Duration(seconds: 4),
      ),
    ]);
    final cubit = build();
    await cubit.load('n1');
    await settle();

    // 10s reais - 2s de silêncio = 8s exibidos.
    expect(cubit.state.displayDurationMs, 8000);
    player.emitPosition(const Duration(seconds: 5));
    await settle();
    expect(cubit.state.displayPositionMs, 3000);

    await cubit.close();
  });
}
