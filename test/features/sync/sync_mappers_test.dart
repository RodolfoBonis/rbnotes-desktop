import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_mappers.dart';

import '../../helpers/test_db.dart';

/// Datas em segundos inteiros (drift guarda DateTime em unix-seconds).
final _t = DateTime(2026, 10, 23, 12);
final _t2 = DateTime(2026, 10, 23, 13);

void main() {
  late AppDatabase a;
  late AppDatabase b;
  late SyncLocalStore storeB;

  setUp(() {
    a = memoryDb();
    b = memoryDb();
    storeB = SyncLocalStore(b);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  /// Insere um pai `note` nos dois bancos (FK dos filhos).
  Future<void> seedParent(String id) async {
    for (final db in [a, b]) {
      await db
          .into(db.notes)
          .insert(
            NotesCompanion.insert(
              id: id,
              createdAt: _t,
              updatedAt: _t,
              status: NoteStatus.ready,
              source: NoteSource.recording,
            ),
          );
    }
  }

  /// Aplica a mudança no banco B e devolve a mudança re-derivada da linha.
  Future<SyncChange> roundTrip(
    SyncChange change,
    Future<SyncChange?> Function(AppDatabase db, String id) read,
  ) async {
    await storeB.applyChange(change);
    final out = await read(b, change.id);
    expect(out, isNotNull, reason: '${change.entity} não persistiu');
    return out!;
  }

  test('note round-trip', () async {
    await a
        .into(a.notes)
        .insert(
          NotesCompanion.insert(
            id: 'n1',
            title: const Value('Kickoff'),
            createdAt: _t,
            updatedAt: _t2,
            durationMs: const Value(18220),
            status: NoteStatus.ready,
            source: NoteSource.recording,
            pinned: const Value(true),
            folderId: const Value('trabalho'),
            favorite: const Value(true),
            kind: const Value(NoteKind.note),
            autoTitle: const Value(true),
            aiStatus: const Value(AiStatus.ready),
            speakersJson: const Value('Você\u001fCamila'),
          ),
        );
    final row = await (a.select(
      a.notes,
    )..where((n) => n.id.equals('n1'))).getSingle();
    final change = SyncMappers.noteToChange(row);
    final back = await roundTrip(change, (db, id) async {
      final r = await (db.select(
        db.notes,
      )..where((n) => n.id.equals(id))).getSingleOrNull();
      return r == null ? null : SyncMappers.noteToChange(r);
    });
    expect(back, change);
  });

  test('segment_set round-trip', () async {
    await seedParent('n1');
    await a
        .into(a.transcriptSegments)
        .insert(
          TranscriptSegmentsCompanion.insert(
            noteId: 'n1',
            speaker: SegmentSpeaker.others,
            startMs: 1000,
            endMs: 2000,
            content: 'olá mundo',
            wordsJson: const Value('[{"text":"olá"}]'),
          ),
        );
    final segs = await (a.select(
      a.transcriptSegments,
    )..where((s) => s.noteId.equals('n1'))).get();
    final change = SyncMappers.segmentSetToChange(
      'n1',
      _t2,
      deleted: false,
      segments: segs,
    );
    final back = await roundTrip(change, (db, id) async {
      final s = await (db.select(
        db.transcriptSegments,
      )..where((x) => x.noteId.equals(id))).get();
      return SyncMappers.segmentSetToChange(
        id,
        _t2,
        deleted: false,
        segments: s,
      );
    });
    expect(back, change);
  });

  test('folder/action/collection/vocabulary/chat/note_ai round-trip', () async {
    await seedParent('n1');

    // folder
    await a
        .into(a.folders)
        .insert(
          FoldersCompanion.insert(
            id: 'f1',
            name: 'Trabalho',
            colorHex: '#2F6BEB',
            sortOrder: const Value(3),
            updatedAt: _t2,
          ),
        );
    final f = await (a.select(
      a.folders,
    )..where((x) => x.id.equals('f1'))).getSingle();
    expect(
      await roundTrip(SyncMappers.folderToChange(f), (db, id) async {
        final r = await (db.select(
          db.folders,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        return r == null ? null : SyncMappers.folderToChange(r);
      }),
      SyncMappers.folderToChange(f),
    );

    // action
    await a
        .into(a.actions)
        .insert(
          ActionsCompanion.insert(
            id: 'a1',
            noteId: 'n1',
            content: 'ligar para a Camila',
            owner: const Value('Você'),
            due: Value(_t2),
            orderIndex: const Value(2),
            updatedAt: _t2,
          ),
        );
    final act = await (a.select(
      a.actions,
    )..where((x) => x.id.equals('a1'))).getSingle();
    expect(
      await roundTrip(SyncMappers.actionToChange(act), (db, id) async {
        final r = await (db.select(
          db.actions,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        return r == null ? null : SyncMappers.actionToChange(r);
      }),
      SyncMappers.actionToChange(act),
    );

    // collection
    await a
        .into(a.collections)
        .insert(
          CollectionsCompanion.insert(
            id: 'c1',
            label: 'Reuniões',
            ruleText: 'mais de uma pessoa',
            ruleJson: '{"minSpeakers":2}',
            kind: const Value('tasks'),
            builtin: const Value(true),
            updatedAt: _t2,
          ),
        );
    final col = await (a.select(
      a.collections,
    )..where((x) => x.id.equals('c1'))).getSingle();
    expect(
      await roundTrip(SyncMappers.collectionToChange(col), (db, id) async {
        final r = await (db.select(
          db.collections,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        return r == null ? null : SyncMappers.collectionToChange(r);
      }),
      SyncMappers.collectionToChange(col),
    );

    // vocabulary
    await a
        .into(a.vocabulary)
        .insert(
          VocabularyCompanion.insert(id: 'v1', term: 'Thaís', updatedAt: _t2),
        );
    final voc = await (a.select(
      a.vocabulary,
    )..where((x) => x.id.equals('v1'))).getSingle();
    expect(
      await roundTrip(SyncMappers.vocabularyToChange(voc), (db, id) async {
        final r = await (db.select(
          db.vocabulary,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        return r == null ? null : SyncMappers.vocabularyToChange(r);
      }),
      SyncMappers.vocabularyToChange(voc),
    );

    // chat_message
    await a
        .into(a.chatMessages)
        .insert(
          ChatMessagesCompanion.insert(
            id: 'm1',
            noteId: 'n1',
            role: ChatRole.ai,
            content: 'claro!',
            citesJson: const Value('[1000,2000]'),
            createdAt: _t,
            updatedAt: _t2,
          ),
        );
    final msg = await (a.select(
      a.chatMessages,
    )..where((x) => x.id.equals('m1'))).getSingle();
    expect(
      await roundTrip(SyncMappers.chatMessageToChange(msg), (db, id) async {
        final r = await (db.select(
          db.chatMessages,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        return r == null ? null : SyncMappers.chatMessageToChange(r);
      }),
      SyncMappers.chatMessageToChange(msg),
    );

    // note_ai
    await a
        .into(a.noteAiTable)
        .insert(
          NoteAiTableCompanion.insert(
            noteId: 'n1',
            json: '{"title":"Kickoff","tldr":"resumo"}',
            updatedAt: _t2,
          ),
        );
    final nai = await (a.select(
      a.noteAiTable,
    )..where((x) => x.noteId.equals('n1'))).getSingle();
    expect(
      await roundTrip(SyncMappers.noteAiToChange(nai), (db, id) async {
        final r = await (db.select(
          db.noteAiTable,
        )..where((x) => x.noteId.equals(id))).getSingleOrNull();
        return r == null ? null : SyncMappers.noteAiToChange(r);
      }),
      SyncMappers.noteAiToChange(nai),
    );
  });

  group('formatos gravados pelo servidor', () {
    final at = DateTime.utc(2026, 10, 24, 1, 10);

    test('note_ai puro (NoteAi direto) não vira {} no pull', () {
      final c = SyncChange(
        entity: 'note_ai',
        id: 'n-1',
        updatedAt: at,
        deleted: false,
        data: {
          'title': 'Enviar pull request do Gemini ao time',
          'tldr': 'Lembrete para enviar amanhã o pull request.',
          'points': ['Enviar o PR amanhã.'],
        },
      );
      final json = SyncMappers.noteAiCompanion(c).json.value;
      expect(json, contains('Enviar pull request do Gemini ao time'));
      expect(json, isNot('{}'));
    });

    test('note_ai no formato do app ({noteId, aiJson}) continua igual', () {
      final c = SyncChange(
        entity: 'note_ai',
        id: 'n-1',
        updatedAt: at,
        deleted: false,
        data: {'noteId': 'n-1', 'aiJson': '{"title":"T","tldr":"R"}'},
      );
      expect(
        SyncMappers.noteAiCompanion(c).json.value,
        '{"title":"T","tldr":"R"}',
      );
    });

    test('chat_message do assistente (threadId/text/cites) é lido', () {
      final c = SyncChange(
        entity: 'chat_message',
        id: 'm-1',
        updatedAt: at,
        deleted: false,
        data: {
          'threadId': 'n-1',
          'role': 'assistant',
          'text': 'Você ficou de enviar o PR.',
          'cites': [
            {'atMs': 188000},
            {'atMs': 352000},
          ],
          'createdAt': '2026-10-24T01:10:00Z',
        },
      );
      final m = SyncMappers.chatMessageCompanion(c);
      expect(m.noteId.value, 'n-1');
      expect(m.role.value, ChatRole.ai);
      expect(m.content.value, 'Você ficou de enviar o PR.');
      expect(m.citesJson.value, '[188000,352000]');
    });
  });
}
