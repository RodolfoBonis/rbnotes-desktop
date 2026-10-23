import 'package:drift/drift.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/sync/data/sync_client.dart';

/// Nomes das entidades sincronizáveis (iguais ao contrato/backend).
abstract final class SyncEntities {
  static const note = 'note';
  static const segmentSet = 'segment_set';
  static const folder = 'folder';
  static const action = 'action';
  static const collection = 'collection';
  static const vocabulary = 'vocabulary';
  static const chatMessage = 'chat_message';
  static const noteAi = 'note_ai';

  static const List<String> all = [
    note,
    segmentSet,
    folder,
    action,
    collection,
    vocabulary,
    chatMessage,
    noteAi,
  ];
}

/// Conversão drift ↔ `SyncChange.data` (camelCase), nos dois sentidos.
///
/// O servidor guarda `data` opaco (só lê `note.data.title` para o índice de
/// busca), então o desktop define a forma canônica. Caminhos de áudio locais
/// (`playbackPath`/`micWavPath`/`systemWavPath`) **não** são sincronizados — o
/// áudio vai por `/notes/{id}/audio`.
abstract final class SyncMappers {
  // ---------------- note ----------------

  static SyncChange noteToChange(NoteRow n) => SyncChange(
    entity: SyncEntities.note,
    id: n.id,
    updatedAt: n.updatedAt,
    deleted: n.deleted,
    data: {
      'title': n.title,
      'createdAt': n.createdAt.toUtc().toIso8601String(),
      'durationMs': n.durationMs,
      'status': n.status.name,
      'source': n.source.name,
      'pinned': n.pinned,
      'folderId': n.folderId,
      'favorite': n.favorite,
      'kind': n.kind.name,
      'autoTitle': n.autoTitle,
      'aiStatus': n.aiStatus.name,
      'speakersJson': n.speakersJson,
    },
  );

  static NotesCompanion noteCompanion(SyncChange c) {
    final d = c.data;
    return NotesCompanion(
      id: Value(c.id),
      title: Value((d['title'] as String?) ?? ''),
      createdAt: Value(_date(d['createdAt']) ?? c.updatedAt),
      updatedAt: Value(c.updatedAt),
      durationMs: Value((d['durationMs'] as num?)?.toInt() ?? 0),
      status: Value(_enum(NoteStatus.values, d['status'], NoteStatus.ready)),
      source: Value(
        _enum(NoteSource.values, d['source'], NoteSource.recording),
      ),
      pinned: Value((d['pinned'] as bool?) ?? false),
      folderId: Value(d['folderId'] as String?),
      favorite: Value((d['favorite'] as bool?) ?? false),
      kind: Value(_enum(NoteKind.values, d['kind'], NoteKind.note)),
      autoTitle: Value((d['autoTitle'] as bool?) ?? false),
      aiStatus: Value(_enum(AiStatus.values, d['aiStatus'], AiStatus.none)),
      speakersJson: Value(d['speakersJson'] as String?),
      deleted: Value(c.deleted),
    );
  }

  // ---------------- segment_set (id = noteId) ----------------

  static SyncChange segmentSetToChange(
    String noteId,
    DateTime updatedAt, {
    required bool deleted,
    required List<SegmentRow> segments,
  }) => SyncChange(
    entity: SyncEntities.segmentSet,
    id: noteId,
    updatedAt: updatedAt,
    deleted: deleted,
    data: {
      'noteId': noteId,
      'segments': [
        for (final s in segments)
          {
            'speaker': s.speaker.name,
            'startMs': s.startMs,
            'endMs': s.endMs,
            'content': s.content,
            'wordsJson': s.wordsJson,
          },
      ],
    },
  );

  static List<TranscriptSegmentsCompanion> segmentCompanions(SyncChange c) {
    final raw = (c.data['segments'] as List?) ?? const [];
    return [
      for (final e in raw.whereType<Map<String, dynamic>>())
        TranscriptSegmentsCompanion.insert(
          noteId: c.id,
          speaker: _enum(
            SegmentSpeaker.values,
            e['speaker'],
            SegmentSpeaker.me,
          ),
          startMs: (e['startMs'] as num?)?.toInt() ?? 0,
          endMs: (e['endMs'] as num?)?.toInt() ?? 0,
          content: (e['content'] as String?) ?? '',
          wordsJson: Value(e['wordsJson'] as String?),
        ),
    ];
  }

  // ---------------- folder ----------------

  static SyncChange folderToChange(FolderRow f) => SyncChange(
    entity: SyncEntities.folder,
    id: f.id,
    updatedAt: f.updatedAt,
    deleted: f.deleted,
    data: {
      'name': f.name,
      'colorHex': f.colorHex,
      'sortOrder': f.sortOrder,
      'hidden': f.hidden,
    },
  );

  static FoldersCompanion folderCompanion(SyncChange c) {
    final d = c.data;
    return FoldersCompanion(
      id: Value(c.id),
      name: Value((d['name'] as String?) ?? ''),
      colorHex: Value((d['colorHex'] as String?) ?? '#8A7A66'),
      sortOrder: Value((d['sortOrder'] as num?)?.toInt() ?? 0),
      hidden: Value((d['hidden'] as bool?) ?? false),
      updatedAt: Value(c.updatedAt),
      deleted: Value(c.deleted),
    );
  }

  // ---------------- action ----------------

  static SyncChange actionToChange(ActionRow a) => SyncChange(
    entity: SyncEntities.action,
    id: a.id,
    updatedAt: a.updatedAt,
    deleted: a.deleted,
    data: {
      'noteId': a.noteId,
      'content': a.content,
      'owner': a.owner,
      'due': a.due?.toUtc().toIso8601String(),
      'done': a.done,
      'snoozedUntil': a.snoozedUntil?.toUtc().toIso8601String(),
      'dismissed': a.dismissed,
      'orderIndex': a.orderIndex,
    },
  );

  static ActionsCompanion actionCompanion(SyncChange c) {
    final d = c.data;
    return ActionsCompanion(
      id: Value(c.id),
      noteId: Value((d['noteId'] as String?) ?? ''),
      content: Value((d['content'] as String?) ?? ''),
      owner: Value(d['owner'] as String?),
      due: Value(_date(d['due'])),
      done: Value((d['done'] as bool?) ?? false),
      snoozedUntil: Value(_date(d['snoozedUntil'])),
      dismissed: Value((d['dismissed'] as bool?) ?? false),
      orderIndex: Value((d['orderIndex'] as num?)?.toInt() ?? 0),
      updatedAt: Value(c.updatedAt),
      deleted: Value(c.deleted),
    );
  }

  // ---------------- collection ----------------

  static SyncChange collectionToChange(CollectionRow c) => SyncChange(
    entity: SyncEntities.collection,
    id: c.id,
    updatedAt: c.updatedAt,
    deleted: c.deleted,
    data: {
      'label': c.label,
      'ruleText': c.ruleText,
      'ruleJson': c.ruleJson,
      'kind': c.kind,
      'builtin': c.builtin,
      'sortOrder': c.sortOrder,
    },
  );

  static CollectionsCompanion collectionCompanion(SyncChange c) {
    final d = c.data;
    return CollectionsCompanion(
      id: Value(c.id),
      label: Value((d['label'] as String?) ?? ''),
      ruleText: Value((d['ruleText'] as String?) ?? ''),
      ruleJson: Value((d['ruleJson'] as String?) ?? '{}'),
      kind: Value(d['kind'] as String?),
      builtin: Value((d['builtin'] as bool?) ?? false),
      sortOrder: Value((d['sortOrder'] as num?)?.toInt() ?? 0),
      updatedAt: Value(c.updatedAt),
      deleted: Value(c.deleted),
    );
  }

  // ---------------- vocabulary ----------------

  static SyncChange vocabularyToChange(VocabularyRow v) => SyncChange(
    entity: SyncEntities.vocabulary,
    id: v.id,
    updatedAt: v.updatedAt,
    deleted: v.deleted,
    data: {'term': v.term},
  );

  static VocabularyCompanion vocabularyCompanion(SyncChange c) =>
      VocabularyCompanion(
        id: Value(c.id),
        term: Value((c.data['term'] as String?) ?? ''),
        updatedAt: Value(c.updatedAt),
        deleted: Value(c.deleted),
      );

  // ---------------- chat_message ----------------

  static SyncChange chatMessageToChange(ChatMessageRow m) => SyncChange(
    entity: SyncEntities.chatMessage,
    id: m.id,
    updatedAt: m.updatedAt,
    deleted: m.deleted,
    data: {
      'noteId': m.noteId,
      'role': m.role.name,
      'content': m.content,
      'citesJson': m.citesJson,
      'createdAt': m.createdAt.toUtc().toIso8601String(),
    },
  );

  static ChatMessagesCompanion chatMessageCompanion(SyncChange c) {
    final d = c.data;
    return ChatMessagesCompanion(
      id: Value(c.id),
      noteId: Value((d['noteId'] as String?) ?? ''),
      role: Value(_enum(ChatRole.values, d['role'], ChatRole.ai)),
      content: Value((d['content'] as String?) ?? ''),
      citesJson: Value(d['citesJson'] as String?),
      createdAt: Value(_date(d['createdAt']) ?? c.updatedAt),
      updatedAt: Value(c.updatedAt),
      deleted: Value(c.deleted),
    );
  }

  // ---------------- note_ai (id = noteId) ----------------

  static SyncChange noteAiToChange(NoteAiRow r) => SyncChange(
    entity: SyncEntities.noteAi,
    id: r.noteId,
    updatedAt: r.updatedAt,
    deleted: false,
    data: {'noteId': r.noteId, 'aiJson': r.json},
  );

  static NoteAiTableCompanion noteAiCompanion(SyncChange c) =>
      NoteAiTableCompanion(
        noteId: Value(c.id),
        json: Value((c.data['aiJson'] as String?) ?? '{}'),
        updatedAt: Value(c.updatedAt),
      );

  // ---------------- helpers ----------------

  static DateTime? _date(Object? v) =>
      v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

  static T _enum<T extends Enum>(List<T> values, Object? raw, T fallback) {
    final name = raw?.toString();
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
