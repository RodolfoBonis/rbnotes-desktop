import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/security/data/note_cipher.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';
import 'package:rbnotes/features/sync/data/sync_crypto.dart';
import 'package:rbnotes/features/sync/data/sync_mappers.dart';

/// Lê mudanças locais (para o push) e aplica mudanças remotas (pull/conflitos)
/// no drift, com LWW por `updatedAt`.
///
/// O "o que mudou" do push vem de uma marca d'água (`since`): toda linha com
/// `updatedAt` posterior entra. Reenviar uma linha já conhecida é idempotente
/// no servidor (mesmo `updatedAt` + mesmo `data`), então um eventual eco de
/// uma mudança recém-aplicada no pull não causa problema.
///
/// O `segment_set` tem **marca d'água própria** no `sync_meta` (não herda a da
/// nota): assim uma edição só de segmentos sincroniza mesmo sem tocar a nota, e
/// uma edição da nota em outro dispositivo não arrasta segmentos stale por cima
/// de uma versão mais nova (convergência LWW correta).
class SyncLocalStore {
  SyncLocalStore(this._db, {SyncCrypto? crypto}) : _crypto = crypto;

  final AppDatabase _db;

  /// Cifra o `data` das notas bloqueadas no push e decifra no pull. Null =
  /// local-first sem cifra (ou backend sem a trava por nota ligada).
  final SyncCrypto? _crypto;

  /// Coleta até [limit] mudanças locais com `updatedAt > since`, em ordem
  /// crescente de `updatedAt` (determinística).
  Future<List<SyncChange>> collectChanges({
    DateTime? since,
    int limit = 400,
  }) async {
    bool fresh(DateTime updatedAt) => since == null || updatedAt.isAfter(since);
    final changes = <SyncChange>[];

    final notes = await _db.select(_db.notes).get();
    final lockedIds = {
      for (final n in notes)
        if (n.locked) n.id,
    };
    for (final n in notes) {
      if (fresh(n.updatedAt)) changes.add(SyncMappers.noteToChange(n));
      // segment_set tem timestamp próprio; na ausência de registro (notas
      // legadas) cai para o da nota.
      final segAt = await _segmentSetUpdatedAt(n.id) ?? n.updatedAt;
      if (!fresh(segAt)) continue;
      final segs =
          await (_db.select(_db.transcriptSegments)
                ..where((s) => s.noteId.equals(n.id))
                ..orderBy([(s) => OrderingTerm.asc(s.startMs)]))
              .get();
      changes.add(
        SyncMappers.segmentSetToChange(
          n.id,
          segAt,
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
    for (final e in await _db.select(_db.diaryEntries).get()) {
      if (fresh(e.updatedAt)) changes.add(SyncMappers.diaryEntryToChange(e));
    }
    for (final t in await _db.select(_db.tags).get()) {
      if (fresh(t.updatedAt)) changes.add(SyncMappers.tagToChange(t));
    }
    for (final nt in await _db.select(_db.noteTags).get()) {
      if (fresh(nt.updatedAt)) changes.add(SyncMappers.noteTagToChange(nt));
    }

    changes.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final trimmed = changes.length > limit
        ? changes.sublist(0, limit)
        : changes;
    final crypto = _crypto;
    if (crypto == null) return trimmed;
    return crypto.encryptOutgoing(trimmed, lockedIds);
  }

  /// Marca **todas** as entidades como excluídas (tombstones) com `updatedAt`
  /// = agora, para o próximo push propagar a exclusão ao servidor. Usado por
  /// "Apagar todos os dados". Também marca o `segment_set` de cada nota.
  Future<void> softDeleteAll({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final del = Value(at);
    await _db.transaction(() async {
      await _db
          .update(_db.notes)
          .write(
            NotesCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.folders)
          .write(
            FoldersCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.actions)
          .write(
            ActionsCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.collections)
          .write(
            CollectionsCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.vocabulary)
          .write(
            VocabularyCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.chatMessages)
          .write(
            ChatMessagesCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.diaryEntries)
          .write(
            DiaryEntriesCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.tags)
          .write(
            TagsCompanion(deleted: const Value(true), updatedAt: del),
          );
      await _db
          .update(_db.noteTags)
          .write(
            NoteTagsCompanion(deleted: const Value(true), updatedAt: del),
          );
      // segment_set tem marca d'água própria no sync_meta: marca como excluído
      // com o mesmo instante para o push enviar o tombstone dos segmentos.
      await _db
          .update(_db.syncMeta)
          .write(
            SyncMetaCompanion(deleted: const Value(true), updatedAt: del),
          );
    });
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
  Future<void> applyChange(SyncChange rawChange) async {
    final crypto = _crypto;
    final c = crypto == null
        ? rawChange
        : await crypto.decryptIncoming(rawChange);
    final local = await _localUpdatedAt(c.entity, c.id);
    if (local != null && local.isAfter(c.updatedAt)) return;
    // Sem a chave, um envelope cifrado não pôde ser decifrado: a nota vira um
    // marcador "bloqueada em outro Mac" e os filhos cifrados são ignorados.
    if (NoteCipher.isEncrypted(c.data)) {
      if (c.entity == SyncEntities.note) {
        await _db
            .into(_db.notes)
            .insertOnConflictUpdate(_lockedElsewhereCompanion(c));
      }
      return;
    }
    switch (c.entity) {
      case SyncEntities.note:
        await _db
            .into(_db.notes)
            .insertOnConflictUpdate(SyncMappers.noteCompanion(c));
      case SyncEntities.segmentSet:
        await _applySegmentSet(c);
        // Persiste o timestamp próprio do conjunto para o próximo LWW/push.
        await _writeSegmentSetMeta(c.id, c.updatedAt, deleted: c.deleted);
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
      case SyncEntities.diaryEntry:
        await _db
            .into(_db.diaryEntries)
            .insertOnConflictUpdate(SyncMappers.diaryEntryCompanion(c));
      case SyncEntities.tag:
        await _db
            .into(_db.tags)
            .insertOnConflictUpdate(SyncMappers.tagCompanion(c));
      case SyncEntities.noteTag:
        final noteId = c.data['noteId'] as String?;
        final tagId = c.data['tagId'] as String?;
        if (await _noteMissing(noteId) || await _tagMissing(tagId)) return;
        await _db
            .into(_db.noteTags)
            .insertOnConflictUpdate(SyncMappers.noteTagCompanion(c));
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
        final r = await (_db.select(
          _db.notes,
        )..where((n) => n.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.segmentSet:
        // segment_set compara contra sua própria marca d'água, não a da nota.
        return _segmentSetUpdatedAt(id);
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
      case SyncEntities.diaryEntry:
        final r = await (_db.select(
          _db.diaryEntries,
        )..where((e) => e.day.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.tag:
        final r = await (_db.select(
          _db.tags,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        return r?.updatedAt;
      case SyncEntities.noteTag:
        final parts = id.split(':');
        if (parts.length < 2) return null;
        final r =
            await (_db.select(_db.noteTags)..where(
                  (nt) =>
                      nt.noteId.equals(parts.first) & nt.tagId.equals(parts[1]),
                ))
                .getSingleOrNull();
        return r?.updatedAt;
    }
    return null;
  }

  Future<bool> _tagMissing(String? tagId) async {
    if (tagId == null || tagId.isEmpty) return true;
    final row = await (_db.select(
      _db.tags,
    )..where((t) => t.id.equals(tagId))).getSingleOrNull();
    return row == null;
  }

  /// Marca d'água própria do `segment_set` da nota (`null` se nunca gravada).
  Future<DateTime?> _segmentSetUpdatedAt(String noteId) async {
    final r =
        await (_db.select(_db.syncMeta)..where(
              (m) =>
                  m.entity.equals(SyncEntities.segmentSet) &
                  m.entityId.equals(noteId),
            ))
            .getSingleOrNull();
    return r?.updatedAt;
  }

  Future<void> _writeSegmentSetMeta(
    String noteId,
    DateTime at, {
    required bool deleted,
  }) {
    return _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            entity: SyncEntities.segmentSet,
            entityId: noteId,
            updatedAt: at,
            deleted: Value(deleted),
          ),
        );
  }

  /// Nota cujo conteúdo chegou cifrado e não pôde ser decifrado (sem a chave):
  /// um marcador bloqueado, com o conteúdo vazio, até a chave ser importada.
  NotesCompanion _lockedElsewhereCompanion(SyncChange c) => NotesCompanion(
    id: Value(c.id),
    title: const Value(''),
    createdAt: Value(c.updatedAt),
    updatedAt: Value(c.updatedAt),
    status: const Value(NoteStatus.ready),
    source: const Value(NoteSource.recording),
    locked: const Value(true),
    deleted: Value(c.deleted),
  );

  static int _priority(String entity) => switch (entity) {
    SyncEntities.note || SyncEntities.folder => 0,
    SyncEntities.collection || SyncEntities.vocabulary => 0,
    SyncEntities.tag || SyncEntities.diaryEntry => 0,
    _ => 1,
  };
}
