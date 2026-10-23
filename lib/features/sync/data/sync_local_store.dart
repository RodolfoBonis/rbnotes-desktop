import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_mappers.dart';

/// Lê mudanças locais (para o push) e aplica mudanças remotas (pull/conflitos)
/// no drift, com LWW por `updatedAt`.
///
/// O "o que mudou" do push vem de uma marca d'água (`since`): toda linha com
/// `updatedAt` posterior entra. Reenviar uma linha já conhecida é idempotente
/// no servidor (mesmo `updatedAt` + mesmo `data`), então um eventual eco de
/// uma mudança recém-aplicada no pull não causa problema.
class SyncLocalStore {
  SyncLocalStore(this._db);

  final AppDatabase _db;

  /// Coleta até [limit] mudanças locais com `updatedAt > since`, em ordem
  /// crescente de `updatedAt` (determinística).
  Future<List<SyncChange>> collectChanges({
    DateTime? since,
    int limit = 400,
  }) async {
    bool fresh(DateTime updatedAt) => since == null || updatedAt.isAfter(since);
    final changes = <SyncChange>[];

    final notes = await _db.select(_db.notes).get();
    for (final n in notes) {
      if (!fresh(n.updatedAt)) continue;
      changes.add(SyncMappers.noteToChange(n));
      final segs =
          await (_db.select(_db.transcriptSegments)
                ..where((s) => s.noteId.equals(n.id))
                ..orderBy([(s) => OrderingTerm.asc(s.startMs)]))
              .get();
      changes.add(
        SyncMappers.segmentSetToChange(
          n.id,
          n.updatedAt,
          deleted: n.deleted,
          segments: segs,
        ),
      );
    }
    for (final f in await _db.select(_db.folders).get()) {
      if (fresh(f.updatedAt)) changes.add(SyncMappers.folderToChange(f));
    }
    for (final a in await _db.select(_db.actions).get()) {
      if (fresh(a.updatedAt)) changes.add(SyncMappers.actionToChange(a));
    }
    for (final c in await _db.select(_db.collections).get()) {
      if (fresh(c.updatedAt)) changes.add(SyncMappers.collectionToChange(c));
    }
    for (final v in await _db.select(_db.vocabulary).get()) {
      if (fresh(v.updatedAt)) changes.add(SyncMappers.vocabularyToChange(v));
    }
    for (final m in await _db.select(_db.chatMessages).get()) {
      if (fresh(m.updatedAt)) changes.add(SyncMappers.chatMessageToChange(m));
    }
    for (final r in await _db.select(_db.noteAiTable).get()) {
      if (fresh(r.updatedAt)) changes.add(SyncMappers.noteAiToChange(r));
    }

    changes.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return changes.length > limit ? changes.sublist(0, limit) : changes;
  }

  /// Maior `updatedAt` entre as mudanças (nova marca d'água após o push).
  DateTime? maxUpdatedAt(List<SyncChange> changes) {
    DateTime? max;
    for (final c in changes) {
      if (max == null || c.updatedAt.isAfter(max)) max = c.updatedAt;
    }
    return max;
  }

  /// Aplica mudanças remotas (pull/conflitos). Pais (note/folder/...) antes dos
  /// filhos (segment_set/action/chat_message/note_ai) para respeitar as FKs.
  Future<void> applyAll(List<SyncChange> changes) async {
    final ordered = [...changes]
      ..sort((a, b) => _priority(a.entity).compareTo(_priority(b.entity)));
    for (final c in ordered) {
      await applyChange(c);
    }
  }

  /// Aplica uma mudança com LWW: ignora se a versão local é mais nova.
  Future<void> applyChange(SyncChange c) async {
    final local = await _localUpdatedAt(c.entity, c.id);
    if (local != null && local.isAfter(c.updatedAt)) return;
    switch (c.entity) {
      case SyncEntities.note:
        await _db
            .into(_db.notes)
            .insertOnConflictUpdate(SyncMappers.noteCompanion(c));
      case SyncEntities.segmentSet:
        await _applySegmentSet(c);
      case SyncEntities.folder:
        await _db
            .into(_db.folders)
            .insertOnConflictUpdate(SyncMappers.folderCompanion(c));
      case SyncEntities.action:
        if (await _noteMissing(c.data['noteId'] as String?)) return;
        await _db
            .into(_db.actions)
            .insertOnConflictUpdate(SyncMappers.actionCompanion(c));
      case SyncEntities.collection:
        await _db
            .into(_db.collections)
            .insertOnConflictUpdate(SyncMappers.collectionCompanion(c));
      case SyncEntities.vocabulary:
        await _db
            .into(_db.vocabulary)
            .insertOnConflictUpdate(SyncMappers.vocabularyCompanion(c));
      case SyncEntities.chatMessage:
        if (await _noteMissing(c.data['noteId'] as String?)) return;
        await _db
            .into(_db.chatMessages)
            .insertOnConflictUpdate(SyncMappers.chatMessageCompanion(c));
      case SyncEntities.noteAi:
        if (await _noteMissing(c.id)) return;
        if (c.deleted) {
          await (_db.delete(
            _db.noteAiTable,
          )..where((t) => t.noteId.equals(c.id))).go();
        } else {
          await _db
              .into(_db.noteAiTable)
              .insertOnConflictUpdate(SyncMappers.noteAiCompanion(c));
        }
    }
    if (c.entity == SyncEntities.note) {
      await _db.recomposeSearchBody(c.id);
    }
  }

  Future<void> _applySegmentSet(SyncChange c) async {
    if (await _noteMissing(c.id)) return;
    await _db.transaction(() async {
      await (_db.delete(
        _db.transcriptSegments,
      )..where((s) => s.noteId.equals(c.id))).go();
      if (!c.deleted) {
        await _db.batch(
          (b) => b.insertAll(
            _db.transcriptSegments,
            SyncMappers.segmentCompanions(c),
          ),
        );
      }
      await _db.recomposeSearchBody(c.id);
    });
  }

  Future<bool> _noteMissing(String? noteId) async {
    if (noteId == null || noteId.isEmpty) return true;
    final row = await (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(noteId))).getSingleOrNull();
    return row == null;
  }

  Future<DateTime?> _localUpdatedAt(String entity, String id) async {
    switch (entity) {
      case SyncEntities.note:
      case SyncEntities.segmentSet:
        final r = await (_db.select(
          _db.notes,
        )..where((n) => n.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.folder:
        final r = await (_db.select(
          _db.folders,
        )..where((f) => f.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.action:
        final r = await (_db.select(
          _db.actions,
        )..where((a) => a.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.collection:
        final r = await (_db.select(
          _db.collections,
        )..where((x) => x.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.vocabulary:
        final r = await (_db.select(
          _db.vocabulary,
        )..where((v) => v.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.chatMessage:
        final r = await (_db.select(
          _db.chatMessages,
        )..where((m) => m.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.noteAi:
        final r = await (_db.select(
          _db.noteAiTable,
        )..where((t) => t.noteId.equals(id))).getSingleOrNull();
        return r?.updatedAt;
    }
    return null;
  }

  static int _priority(String entity) => switch (entity) {
    SyncEntities.note || SyncEntities.folder => 0,
    SyncEntities.collection || SyncEntities.vocabulary => 0,
    _ => 1,
  };
}
