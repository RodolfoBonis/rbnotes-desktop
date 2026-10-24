import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/diary/data/diary_repository.dart';
import 'package:rbnotes/features/library/data/demo_seeder.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_entities.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late DemoSeeder seeder;

  setUp(() {
    db = memoryDb();
    notes = NoteRepository(db);
    seeder = DemoSeeder(
      notes: notes,
      noteAi: NoteAiRepository(db),
      library: LibraryRepository(db),
      diary: DiaryRepository(db),
    );
  });
  tearDown(() => db.close());

  test('purgeSeedNotes remove as notas de seed intocadas', () async {
    await seeder.seedIfEmpty();
    expect(await notes.getNote('n1'), isNotNull);

    final removed = await seeder.purgeSeedNotes();
    expect(removed, greaterThan(0));
    for (final id in seeder.seedNoteIds) {
      expect(await notes.getNote(id), isNull, reason: 'seed sumir');
    }
    final meta = await db.select(db.syncMeta).get();
    expect(meta.where((m) => m.entityId == 'n1'), isEmpty);
  });

  test('purgeSeedNotes preserva uma nota de seed editada', () async {
    await seeder.seedIfEmpty();
    await notes.updateTitle('n1', 'Minha reuniao renomeada');

    await seeder.purgeSeedNotes();
    expect(await notes.getNote('n1'), isNotNull);
    expect(await notes.getNote('n2'), isNull);
  });

  test('purgeSeedNotes e idempotente e nao falha em banco sem seed', () async {
    expect(await seeder.purgeSeedNotes(), 0);
  });

  test('purgeSeedNotes manda tombstones dos ids de seed ao servidor', () async {
    final sync = _RecordingSync();
    final s = DemoSeeder(
      notes: notes,
      noteAi: NoteAiRepository(db),
      library: LibraryRepository(db),
      diary: DiaryRepository(db),
      sync: sync,
    );
    await s.seedIfEmpty();
    // n1 editada é preservada e NÃO vira tombstone.
    await notes.updateTitle('n1', 'Editada pelo dono');

    final removed = await s.purgeSeedNotes();
    expect(removed, greaterThan(0));

    expect(sync.pushed.where((c) => c.id == 'n1'), isEmpty);
    expect(await notes.getNote('n1'), isNotNull);

    // n2 (intocada) virou tombstone em note, note_ai e segment_set.
    final n2 = sync.pushed.where((c) => c.id == 'n2').toList();
    expect(n2.map((c) => c.entity).toSet(), {
      SyncEntities.note,
      SyncEntities.noteAi,
      SyncEntities.segmentSet,
    });
    expect(n2.every((c) => c.deleted), isTrue);
    expect(await notes.getNote('n2'), isNull);

    // Só ids fixos do seeder entram.
    final ids = sync.pushed.map((c) => c.id).toSet();
    expect(ids.difference(s.seedNoteIds.toSet()), isEmpty);
  });

  test('purge não apaga local se o push de tombstone falha', () async {
    final s = DemoSeeder(
      notes: notes,
      noteAi: NoteAiRepository(db),
      library: LibraryRepository(db),
      diary: DiaryRepository(db),
      sync: _FailingSync(),
    );
    await s.seedIfEmpty();

    expect(await s.purgeSeedNotes(), 0);
    expect(
      await notes.getNote('n2'),
      isNotNull,
      reason: 'adia a limpeza para o próximo boot',
    );
  });
}

/// Registra os changes enviados ao push (sem rede).
class _RecordingSync implements SyncClient {
  final List<SyncChange> pushed = [];

  @override
  Future<PushResult> push(List<SyncChange> changes) async {
    pushed.addAll(changes);
    return PushResult(
      applied: changes.map((c) => c.id).toList(),
      conflicts: const [],
    );
  }

  @override
  Future<PullResult> pull({String? since}) async =>
      PullResult(changes: const [], cursor: since ?? '0');
}

/// Simula um servidor inalcançável (offline): todo push falha.
class _FailingSync implements SyncClient {
  @override
  Future<PushResult> push(List<SyncChange> changes) async =>
      throw Exception('offline');

  @override
  Future<PullResult> pull({String? since}) async =>
      throw Exception('offline');
}
