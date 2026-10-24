import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/security/data/note_cipher.dart';
import 'package:rbnotes/features/security/data/note_key.dart';
import 'package:rbnotes/features/security/data/note_key_store.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_crypto.dart';
import 'package:rbnotes/features/sync/data/sync_entities.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';

import '../../helpers/test_db.dart';

void main() {
  final key = NoteKey(Uint8List.fromList(List.generate(32, (i) => i + 1)));

  SyncChange note(String id, {bool deleted = false}) => SyncChange(
    entity: SyncEntities.note,
    id: id,
    updatedAt: DateTime(2026, 10, 24),
    deleted: deleted,
    data: deleted ? const {} : {'title': 'Confidencial', 'folderId': 'x'},
  );

  group('SyncCrypto', () {
    test('encrypts only locked note entities, leaves others clear', () async {
      final crypto = SyncCrypto(InMemoryNoteKeyStore(key));
      final out = await crypto.encryptOutgoing(
        [note('locked1'), note('open1')],
        {'locked1'},
      );
      expect(NoteCipher.isEncrypted(out[0].data), isTrue);
      expect(out[0].data.containsKey('title'), isFalse);
      expect(out[1].data['title'], 'Confidencial');
    });

    test('does not encrypt tombstones', () async {
      final crypto = SyncCrypto(InMemoryNoteKeyStore(key));
      final out = await crypto.encryptOutgoing(
        [note('locked1', deleted: true)],
        {'locked1'},
      );
      expect(NoteCipher.isEncrypted(out.single.data), isFalse);
    });

    test('decryptIncoming restores the cleartext with the key', () async {
      final crypto = SyncCrypto(InMemoryNoteKeyStore(key));
      final enc = (await crypto.encryptOutgoing([note('n')], {'n'})).single;
      final back = await crypto.decryptIncoming(enc);
      expect(back.data['title'], 'Confidencial');
    });

    test(
      'without a key, an encrypted change stays encrypted on pull',
      () async {
        final enc = (await SyncCrypto(
          InMemoryNoteKeyStore(key),
        ).encryptOutgoing([note('n')], {'n'})).single;
        final noKey = SyncCrypto(InMemoryNoteKeyStore());
        final back = await noKey.decryptIncoming(enc);
        expect(NoteCipher.isEncrypted(back.data), isTrue);
      },
    );
  });

  group('SyncLocalStore with crypto', () {
    late AppDatabase db;
    late NoteRepository repo;

    setUp(() async {
      db = memoryDb();
      repo = memoryRepo(db);
      await seedNote(db, id: 'secret', title: 'Reunião secreta');
      await seedSegment(db, noteId: 'secret', content: 'texto sensível');
      await repo.setLocked('secret', locked: true);
    });

    tearDown(() => db.close());

    test('collectChanges encrypts the locked note and segments', () async {
      final store = SyncLocalStore(
        db,
        crypto: SyncCrypto(InMemoryNoteKeyStore(key)),
      );
      final changes = await store.collectChanges();
      final noteChange = changes.firstWhere(
        (c) => c.entity == SyncEntities.note && c.id == 'secret',
      );
      final segChange = changes.firstWhere(
        (c) => c.entity == SyncEntities.segmentSet && c.id == 'secret',
      );
      expect(NoteCipher.isEncrypted(noteChange.data), isTrue);
      expect(NoteCipher.isEncrypted(segChange.data), isTrue);
      // No cleartext anywhere in the outgoing payloads.
      final blob = [
        for (final c in changes) c.toJson().toString(),
      ].join();
      expect(blob.contains('sensível'), isFalse);
      expect(blob.contains('secreta'), isFalse);
    });

    test('a second Mac without the key stores a locked placeholder', () async {
      final store = SyncLocalStore(
        db,
        crypto: SyncCrypto(InMemoryNoteKeyStore(key)),
      );
      final encrypted = await store.collectChanges();

      final other = memoryDb();
      addTearDown(other.close);
      final otherStore = SyncLocalStore(
        other,
        crypto: SyncCrypto(InMemoryNoteKeyStore()), // no key
      );
      await otherStore.applyAll(encrypted);

      final row = await (other.select(
        other.notes,
      )..where((n) => n.id.equals('secret'))).getSingleOrNull();
      expect(row, isNotNull);
      expect(row!.locked, isTrue);
      expect(row.title, '');
      // The encrypted segments were skipped (no cleartext stored).
      final segs = await (other.select(
        other.transcriptSegments,
      )..where((s) => s.noteId.equals('secret'))).get();
      expect(segs, isEmpty);
    });

    test('a Mac with the key restores the locked note content', () async {
      final store = SyncLocalStore(
        db,
        crypto: SyncCrypto(InMemoryNoteKeyStore(key)),
      );
      final encrypted = await store.collectChanges();

      final other = memoryDb();
      addTearDown(other.close);
      final otherStore = SyncLocalStore(
        other,
        crypto: SyncCrypto(InMemoryNoteKeyStore(key)),
      );
      await otherStore.applyAll(encrypted);

      final row = await (other.select(
        other.notes,
      )..where((n) => n.id.equals('secret'))).getSingle();
      expect(row.title, 'Reunião secreta');
      expect(row.locked, isTrue);
      final segs = await (other.select(
        other.transcriptSegments,
      )..where((s) => s.noteId.equals('secret'))).get();
      expect(segs.single.content, 'texto sensível');
    });
  });
}
