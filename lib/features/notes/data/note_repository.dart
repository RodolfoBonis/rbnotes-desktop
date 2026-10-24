import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/sync/data/sync_entities.dart';

const _tagSep = '\u001f'; // unit separator (campos)
const _tagRec = '\u001e'; // record separator (tags)

const _listWithTagsSql =
    '''
SELECT n.*, (
  SELECT group_concat(
    t.id || '$_tagSep' || t.name || '$_tagSep' || COALESCE(t.emoji, ''),
    '$_tagRec'
  )
  FROM note_tags nt JOIN tags t ON t.id = nt.tag_id
  WHERE nt.note_id = n.id
) AS tag_blob
FROM notes n
WHERE (?1 = '' OR EXISTS (
  SELECT 1 FROM note_tags f WHERE f.note_id = n.id AND f.tag_id = ?1
))
ORDER BY n.pinned DESC, n.created_at DESC''';

/// Resultado de uma correção de palavra (quantas notas e ocorrências).
class WordFixResult {
  const WordFixResult({required this.notes, required this.occurrences});
  final int notes;
  final int occurrences;
}

/// Persistência das notas, segmentos e tags (drift/SQLite).
///
/// Única porta para os dados locais; todas as features dependem desta classe.
class NoteRepository {
  NoteRepository(this._db);

  final AppDatabase _db;

  // ---------- Lista & busca ----------

  /// Notas (pinned primeiro, mais recentes antes), com suas tags.
  /// [tagId] filtra por uma tag.
  Stream<List<NoteListItem>> watchNotes({String? tagId}) {
    return _db
        .customSelect(
          _listWithTagsSql,
          variables: [Variable<String>(tagId ?? '')],
          readsFrom: {_db.notes, _db.tags, _db.noteTags},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => NoteListItem(
                  note: _db.notes.map(row.data),
                  tags: _parseTagBlob(row.read<String?>('tag_blob')),
                ),
              )
              .toList(),
        );
  }

  /// Todas as notas não apagadas, mais recentes primeiro (sidebar/lista v3).
  Stream<List<NoteRow>> watchAllNotes() {
    return (_db.select(_db.notes)
          ..where((n) => n.deleted.equals(false))
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
        .watch();
  }

  Future<List<NoteRow>> getAllNotes() =>
      (_db.select(_db.notes)..where((n) => n.deleted.equals(false))).get();

  Future<List<NoteSearchHit>> search(String query) => _db.search(query);

  // ---------- Detalhe ----------

  Stream<NoteRow?> watchNote(String id) {
    return (_db.select(
      _db.notes,
    )..where((n) => n.id.equals(id))).watchSingleOrNull();
  }

  Stream<List<SegmentRow>> watchSegments(String noteId) {
    return (_db.select(_db.transcriptSegments)
          ..where((s) => s.noteId.equals(noteId))
          ..orderBy([(s) => OrderingTerm.asc(s.startMs)]))
        .watch();
  }

  Stream<List<TagRow>> watchNoteTags(String noteId) {
    final query = _db.select(_db.tags).join([
      innerJoin(_db.noteTags, _db.noteTags.tagId.equalsExp(_db.tags.id)),
    ])..where(_db.noteTags.noteId.equals(noteId));
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_db.tags)).toList(),
    );
  }

  Future<NoteRow?> getNote(String id) =>
      (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  Future<List<NoteRow>> notesWithStatus(NoteStatus status) =>
      (_db.select(_db.notes)..where((n) => n.status.equalsValue(status))).get();

  Future<List<NoteRow>> notesWithAiStatus(AiStatus status) =>
      (_db.select(_db.notes)
            ..where((n) => n.aiStatus.equalsValue(status))
            ..where((n) => n.deleted.equals(false)))
          .get();

  // ---------- Escrita de notas ----------

  Future<void> insertNote(NotesCompanion note) =>
      _db.into(_db.notes).insert(note);

  Future<void> updateTitle(String id, String title, {bool autoTitle = false}) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: Value(title),
        autoTitle: Value(autoTitle),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setPinned(String id, {required bool pinned}) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(pinned: Value(pinned), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setFavorite(String id, {required bool favorite}) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        favorite: Value(favorite),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Bloqueia/desbloqueia a nota por Touch ID. Ao bloquear, remove título e
  /// corpo do índice FTS; ao desbloquear, reindexa. O `updatedAt` é bumpado
  /// para o sync levar a mudança (e cifrar/decifrar no push/pull).
  Future<void> setLocked(String id, {required bool locked}) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        locked: Value(locked),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (locked) {
      await _db.removeFromSearchIndex(id);
    } else {
      await _db.reindexSearch(id);
    }
  }

  Future<void> setFolder(String id, String? folderId) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setKind(String id, NoteKind kind) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(kind: Value(kind), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setAiStatus(String id, AiStatus status) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(aiStatus: Value(status), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setSpeakers(String id, String? speakersJson) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        speakersJson: Value(speakersJson),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setStatus(String id, NoteStatus status) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
    );
  }

  /// Grava caminhos/duração ao encerrar a gravação.
  Future<void> finalizeRecording(
    String id, {
    required int durationMs,
    required String playbackPath,
    required String micWavPath,
    String? systemWavPath,
    NoteStatus status = NoteStatus.transcribing,
  }) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        durationMs: Value(durationMs),
        playbackPath: Value(playbackPath),
        micWavPath: Value(micWavPath),
        systemWavPath: Value(systemWavPath),
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> recoverRecording(
    String id, {
    required int durationMs,
    required String micWavPath,
    String? systemWavPath,
  }) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        durationMs: Value(durationMs),
        micWavPath: Value(micWavPath),
        systemWavPath: Value(systemWavPath),
        status: const Value(NoteStatus.transcribing),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteNote(String id) =>
      (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();

  /// Exclusão para o usuário: marca `deleted = true` e bumpa `updatedAt`, para
  /// a nota sumir da UI (as queries filtram `deleted = false`) e um tombstone
  /// propagar pelo sync. O SyncTrigger dispara no update da tabela `notes`.
  Future<void> softDeleteNote(String id) =>
      (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Remove **localmente** uma nota e todo o seu rastro de sync (sem gerar
  /// tombstone para o servidor). Usado só para limpar dados de seed que nunca
  /// saíram deste dispositivo — ver DemoSeeder.purgeSeedNotes.
  Future<void> purgeLocal(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
      await (_db.delete(
        _db.syncMeta,
      )..where((m) => m.entityId.equals(id))).go();
    });
  }

  /// Zera os caminhos de áudio da nota (mantém o texto). Usado quando "apagar
  /// áudio após transcrever" ou a retenção removem os arquivos mas preservam a
  /// transcrição/resumo.
  Future<void> clearAudioPaths(String id) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      const NotesCompanion(
        playbackPath: Value(null),
        micWavPath: Value(null),
        systemWavPath: Value(null),
      ),
    );
  }

  // ---------- Segmentos ----------

  Future<void> replaceSegments(
    String noteId,
    List<DraftSegment> segments,
  ) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.transcriptSegments,
      )..where((s) => s.noteId.equals(noteId))).go();
      await _db.batch((batch) {
        batch.insertAll(
          _db.transcriptSegments,
          segments.map(
            (s) => TranscriptSegmentsCompanion.insert(
              noteId: noteId,
              speaker: s.speaker,
              startMs: s.startMs,
              endMs: s.endMs,
              content: s.content,
              wordsJson: Value(s.wordsJson),
            ),
          ),
        );
      });
      await _db.recomposeSearchBody(noteId);
      await _touchSegmentSet(noteId, DateTime.now());
    });
  }

  /// Edita o texto de um segmento (edição inline da transcrição), reindexa o
  /// FTS e marca o conjunto de segmentos como alterado para o sync.
  Future<void> updateSegmentContent(
    String noteId,
    int segmentId,
    String content,
  ) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.transcriptSegments,
      )..where((s) => s.id.equals(segmentId))).write(
        TranscriptSegmentsCompanion(content: Value(content)),
      );
      await _db.recomposeSearchBody(noteId);
      await _touchSegmentSet(noteId, DateTime.now());
    });
  }

  Future<List<SegmentRow>> getSegments(String noteId) {
    return (_db.select(_db.transcriptSegments)
          ..where((s) => s.noteId.equals(noteId))
          ..orderBy([(s) => OrderingTerm.asc(s.startMs)]))
        .get();
  }

  /// Conta as ocorrências de [word] e em quantas notas aparece (prévia do
  /// modal "Corrigir palavra").
  Future<WordFixResult> countWord(String word) async {
    if (word.isEmpty) return const WordFixResult(notes: 0, occurrences: 0);
    final segments = await _db.select(_db.transcriptSegments).get();
    final notesSet = <String>{};
    var occ = 0;
    for (final s in segments) {
      final n = word.allMatches(s.content).length;
      if (n > 0) {
        occ += n;
        notesSet.add(s.noteId);
      }
    }
    return WordFixResult(notes: notesSet.length, occurrences: occ);
  }

  /// Corrige uma palavra na transcrição: substitui [from] por [to] na nota
  /// [onlyNoteId] (se dado) ou em todas as notas. Recompõe o índice FTS das
  /// notas afetadas. Retorna quantas notas e ocorrências mudaram.
  Future<WordFixResult> fixWord(
    String from,
    String to, {
    String? onlyNoteId,
  }) async {
    if (from.isEmpty || from == to) {
      return const WordFixResult(notes: 0, occurrences: 0);
    }
    var notesChanged = 0;
    var occurrences = 0;
    await _db.transaction(() async {
      final query = _db.select(_db.transcriptSegments);
      if (onlyNoteId != null) {
        query.where((s) => s.noteId.equals(onlyNoteId));
      }
      final segments = await query.get();
      final touchedNotes = <String>{};
      for (final s in segments) {
        if (!s.content.contains(from)) continue;
        occurrences += from.allMatches(s.content).length;
        touchedNotes.add(s.noteId);
        await (_db.update(
          _db.transcriptSegments,
        )..where((t) => t.id.equals(s.id))).write(
          TranscriptSegmentsCompanion(
            content: Value(s.content.replaceAll(from, to)),
          ),
        );
      }
      final now = DateTime.now();
      for (final noteId in touchedNotes) {
        await _db.recomposeSearchBody(noteId);
        await _touchSegmentSet(noteId, now);
      }
      notesChanged = touchedNotes.length;
    });
    return WordFixResult(notes: notesChanged, occurrences: occurrences);
  }

  /// Marca o `segment_set` da nota como alterado para o sync. O conjunto de
  /// segmentos tem `updatedAt` próprio no `sync_meta` (independente de
  /// `note.updatedAt`), para que uma edição de segmentos convirja por LWW mesmo
  /// quando a nota em si não é tocada, e para que uma edição de nota em outro
  /// dispositivo não sobrescreva segmentos mais novos com os seus (stale).
  Future<void> _touchSegmentSet(String noteId, DateTime at) {
    return _db
        .into(_db.syncMeta)
        .insertOnConflictUpdate(
          SyncMetaCompanion.insert(
            entity: SyncEntities.segmentSet,
            entityId: noteId,
            updatedAt: at,
            deleted: const Value(false),
          ),
        );
  }

  // ---------- Tags ----------

  Stream<List<TagRow>> watchTags() {
    return (_db.select(_db.tags)..orderBy([
          (t) => OrderingTerm.desc(t.pinned),
          (t) => OrderingTerm.asc(t.name),
        ]))
        .watch();
  }

  Future<void> upsertTag(TagsCompanion tag) =>
      _db.into(_db.tags).insertOnConflictUpdate(tag);

  Future<void> deleteTag(String id) =>
      (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();

  Future<void> setTagPinned(String id, {required bool pinned}) {
    return (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(pinned: Value(pinned)),
    );
  }

  Future<void> addTagToNote(String noteId, String tagId) {
    return _db
        .into(_db.noteTags)
        .insertOnConflictUpdate(
          NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
        );
  }

  Future<void> removeTagFromNote(String noteId, String tagId) {
    return (_db.delete(
      _db.noteTags,
    )..where((nt) => nt.noteId.equals(noteId) & nt.tagId.equals(tagId))).go();
  }

  List<TagRow> _parseTagBlob(String? blob) {
    if (blob == null || blob.isEmpty) return [];
    return blob.split(_tagRec).where((r) => r.isNotEmpty).map((record) {
      final parts = record.split(_tagSep);
      final emoji = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
      return TagRow(
        id: parts[0],
        name: parts.length > 1 ? parts[1] : '',
        emoji: emoji,
        pinned: false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        deleted: false,
      );
    }).toList();
  }
}
