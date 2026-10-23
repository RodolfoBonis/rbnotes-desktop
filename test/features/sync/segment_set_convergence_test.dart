import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_entities.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';

import '../../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late SyncLocalStore store;

  final t0 = DateTime(2025, 12, 31);
  final t1 = DateTime(2026, 1, 2);
  final t3 = DateTime(2026, 1, 3);
  final t4 = DateTime(2026, 1, 4);
  final t5 = DateTime(2026, 1, 5);

  setUp(() {
    db = memoryDb();
    notes = NoteRepository(db);
    store = SyncLocalStore(db);
  });
  tearDown(() => db.close());

  Future<void> seedNoteWithLocalSegments() async {
    await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            id: 'n1',
            title: const Value('A'),
            createdAt: t1,
            updatedAt: t1,
            status: NoteStatus.ready,
            source: NoteSource.recording,
          ),
        );
    await db
        .into(db.transcriptSegments)
        .insert(
          TranscriptSegmentsCompanion.insert(
            noteId: 'n1',
            speaker: SegmentSpeaker.me,
            startMs: 0,
            endMs: 1000,
            content: 'local-A',
          ),
        );
    // Marca d'água própria do segment_set (edição local em t3).
    await db
        .into(db.syncMeta)
        .insert(
          SyncMetaCompanion.insert(
            entity: SyncEntities.segmentSet,
            entityId: 'n1',
            updatedAt: t3,
          ),
        );
  }

  SyncChange noteChange(String title, DateTime at) => SyncChange(
    entity: SyncEntities.note,
    id: 'n1',
    updatedAt: at,
    deleted: false,
    data: {'title': title, 'status': 'ready', 'source': 'recording'},
  );

  SyncChange segmentSetChange(String content, DateTime at) => SyncChange(
    entity: SyncEntities.segmentSet,
    id: 'n1',
    updatedAt: at,
    deleted: false,
    data: {
      'noteId': 'n1',
      'segments': [
        {'speaker': 'me', 'startMs': 0, 'endMs': 1000, 'content': content},
      ],
    },
  );

  Future<String> segmentContent() async {
    final segs = await notes.getSegments('n1');
    return segs.single.content;
  }

  test(
    'edição de nota em outro device NÃO sobrescreve segmentos mais novos',
    () async {
      await seedNoteWithLocalSegments();

      // Device B só editou o título (t5). O segment_set de B carrega a marca
      // d'água PRÓPRIA dele (t0), não a da nota — então chega "velho".
      await store.applyAll([
        noteChange('B', t5),
        segmentSetChange('stale-B', t0),
      ]);

      // Título converge para o de B (LWW t5), mas os segmentos locais (t3)
      // vencem o segment_set velho (t0): sem perda de dados.
      expect((await notes.getNote('n1'))!.title, 'B');
      expect(await segmentContent(), 'local-A');
    },
  );

  test('segment_set remoto mais novo é aplicado (edição legítima)', () async {
    await seedNoteWithLocalSegments();

    await store.applyAll([segmentSetChange('new-B', t4)]);

    expect(await segmentContent(), 'new-B');
  });

  test(
    'edição só de segmentos sincroniza mesmo sem a nota ser tocada',
    () async {
      // Nota antiga (t1) sem mexer; só os segmentos mudam agora (via repo, que
      // bumpa a marca d'água própria do segment_set).
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: 'n1',
              createdAt: t1,
              updatedAt: t1,
              status: NoteStatus.ready,
              source: NoteSource.recording,
            ),
          );
      await notes.replaceSegments('n1', const [
        DraftSegment(
          speaker: SegmentSpeaker.me,
          startMs: 0,
          endMs: 500,
          content: 'nova fala',
        ),
      ]);

      // Marca d'água depois da nota, mas antes da edição de segmentos.
      final since = t1.add(const Duration(seconds: 1));
      final changes = await store.collectChanges(since: since);

      final entities = changes.map((c) => c.entity).toSet();
      expect(entities, contains(SyncEntities.segmentSet));
      expect(
        entities,
        isNot(contains(SyncEntities.note)),
        reason: 'a nota não foi tocada, então não entra no push',
      );
    },
  );
}
