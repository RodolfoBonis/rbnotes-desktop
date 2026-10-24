import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
import 'package:rbnotes/features/sync/data/sync_mappers.dart';

import '../../helpers/test_db.dart';

void main() {
  test('migração v5 → v6 adiciona tags.updated_at/deleted', () async {
    final db = memoryDb();
    addTearDown(db.close);
    final cols = await db.customSelect('PRAGMA table_info(tags)').get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, containsAll(['updated_at', 'deleted']));
  });

  group('mappers diário/tags', () {
    test('diary_entry round-trip', () {
      final row = DiaryEntryRow(
        day: '2026-10-24',
        noteId: 'n1',
        promptId: 'prompt_0',
        createdAt: DateTime(2026, 10, 24, 8),
        updatedAt: DateTime(2026, 10, 24, 8),
        deleted: false,
      );
      final change = SyncMappers.diaryEntryToChange(row);
      expect(change.entity, SyncEntities.diaryEntry);
      expect(change.id, '2026-10-24');
      final companion = SyncMappers.diaryEntryCompanion(change);
      expect(companion.noteId.value, 'n1');
      expect(companion.promptId.value, 'prompt_0');
    });

    test('tag round-trip', () {
      final row = TagRow(
        id: 't1',
        name: 'Ideias',
        emoji: '💡',
        pinned: true,
        updatedAt: DateTime(2026, 10, 24),
        deleted: false,
      );
      final change = SyncMappers.tagToChange(row);
      expect(change.id, 't1');
      final companion = SyncMappers.tagCompanion(change);
      expect(companion.name.value, 'Ideias');
      expect(companion.emoji.value, '💡');
      expect(companion.pinned.value, isTrue);
    });

    test('note_tag id combina noteId e tagId', () {
      final row = NoteTagRow(
        noteId: 'n1',
        tagId: 't1',
        updatedAt: DateTime(2026, 10, 24),
        deleted: false,
      );
      final change = SyncMappers.noteTagToChange(row);
      expect(change.id, 'n1:t1');
      final companion = SyncMappers.noteTagCompanion(change);
      expect(companion.noteId.value, 'n1');
      expect(companion.tagId.value, 't1');
    });
  });

  test('round-trip pelo SyncLocalStore (coleta e aplica)', () async {
    final source = memoryDb();
    final target = memoryDb();
    addTearDown(source.close);
    addTearDown(target.close);

    await seedNote(source, id: 'n1', title: 'Nota');
    await source
        .into(source.tags)
        .insert(TagsCompanion.insert(id: 't1', name: 'Ideias'));
    await source
        .into(source.noteTags)
        .insert(
          const NoteTagsCompanion(noteId: Value('n1'), tagId: Value('t1')),
        );
    await source
        .into(source.diaryEntries)
        .insert(
          DiaryEntriesCompanion.insert(
            day: '2026-10-24',
            createdAt: DateTime(2026, 10, 24),
            updatedAt: DateTime(2026, 10, 24),
          ),
        );

    final changes = await SyncLocalStore(source).collectChanges();
    // A nota precede a tag/relação para respeitar as FKs no apply.
    await seedNote(target, id: 'n1', title: 'Nota');
    await SyncLocalStore(target).applyAll(changes);

    expect((await target.select(target.tags).get()).single.name, 'Ideias');
    expect((await target.select(target.noteTags).get()).single.tagId, 't1');
    expect(
      (await target.select(target.diaryEntries).get()).single.day,
      '2026-10-24',
    );
  });
}
