import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';

/// Pastas e coleções inteligentes (drift v3). Fonte única para a sidebar.
class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  // ---------- Pastas ----------

  Stream<List<FolderRow>> watchFolders() =>
      (_db.select(_db.folders)
            ..where((f) => f.deleted.equals(false))
            ..orderBy([(f) => OrderingTerm.asc(f.sortOrder)]))
          .watch();

  Future<List<FolderRow>> getFolders() =>
      (_db.select(_db.folders)..where((f) => f.deleted.equals(false))).get();

  // ---------- Coleções ----------

  Stream<List<CollectionRow>> watchCollections() =>
      (_db.select(_db.collections)
            ..where((c) => c.deleted.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
          .watch();

  Future<List<CollectionRow>> getCollections() => (_db.select(
    _db.collections,
  )..where((c) => c.deleted.equals(false))).get();

  Future<void> upsertCollection(CollectionsCompanion collection) async {
    await _db.into(_db.collections).insertOnConflictUpdate(collection);
  }

  Future<void> deleteCollection(String id) {
    return (_db.update(_db.collections)..where((c) => c.id.equals(id))).write(
      CollectionsCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Garante que as coleções embutidas (Tarefas esquecidas, Reuniões, Ideias
  /// para explorar) existem. Idempotente.
  Future<void> ensureBuiltinCollections() async {
    final now = DateTime.now();
    await _db.batch((b) {
      b.insertAll(_db.collections, [
        CollectionsCompanion.insert(
          id: 'c-forgot',
          label: 'Tarefas esquecidas',
          ruleText: 'Tarefas abertas há mais de 3 dias',
          ruleJson: '{"openActions":true}',
          kind: const Value('tasks'),
          builtin: const Value(true),
          sortOrder: const Value(0),
          updatedAt: now,
        ),
        CollectionsCompanion.insert(
          id: 'c-meet',
          label: 'Reuniões',
          ruleText: 'Notas com mais de uma pessoa falando',
          ruleJson: '{"minSpeakers":2}',
          builtin: const Value(true),
          sortOrder: const Value(1),
          updatedAt: now,
        ),
        CollectionsCompanion.insert(
          id: 'c-ideas',
          label: 'Ideias para explorar',
          ruleText: 'Pasta Ideias com tarefas em aberto',
          ruleJson: '{"folders":["ideias"],"openActions":true}',
          builtin: const Value(true),
          sortOrder: const Value(2),
          updatedAt: now,
        ),
      ], mode: InsertMode.insertOrIgnore);
    });
  }
}
