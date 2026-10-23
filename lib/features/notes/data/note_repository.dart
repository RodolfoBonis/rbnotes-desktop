import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';

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
      innerJoin(
        _db.noteTags,
        _db.noteTags.tagId.equalsExp(_db.tags.id),
      ),
    ])..where(_db.noteTags.noteId.equals(noteId));
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_db.tags)).toList(),
    );
  }

  Future<NoteRow?> getNote(String id) =>
      (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();

  /// Todas as notas num dado [status] (ex.: `recording`/`transcribing`
  /// pendentes após um crash, para recuperação no boot).
  Future<List<NoteRow>> notesWithStatus(NoteStatus status) =>
      (_db.select(_db.notes)..where((n) => n.status.equalsValue(status))).get();

  // ---------- Escrita de notas ----------

  Future<void> insertNote(NotesCompanion note) =>
      _db.into(_db.notes).insert(note);

  Future<void> updateTitle(String id, String title) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(title: Value(title), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setPinned(String id, {required bool pinned}) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(pinned: Value(pinned), updatedAt: Value(DateTime.now())),
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

  /// Atualiza uma nota órfã (status `recording` após crash) com os caminhos dos
  /// `.wav` recuperados e a marca como `transcribing`. Diferente de
  /// [finalizeRecording], não exige `playbackPath` (pode não haver `.m4a`).
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

  // ---------- Segmentos ----------

  /// Substitui todos os segmentos de uma nota (ordem por [DraftSegment.startMs]
  /// fica a cargo de quem monta a lista) e recompõe o índice de busca numa
  /// única passada, dentro da mesma transação.
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
            ),
          ),
        );
      });
      await _db.recomposeSearchBody(noteId);
    });
  }

  Future<List<SegmentRow>> getSegments(String noteId) {
    return (_db.select(_db.transcriptSegments)
          ..where((s) => s.noteId.equals(noteId))
          ..orderBy([(s) => OrderingTerm.asc(s.startMs)]))
        .get();
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
      );
    }).toList();
  }
}
