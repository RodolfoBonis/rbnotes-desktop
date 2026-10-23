import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:drift/drift.dart' show Value;
import 'package:equatable/equatable.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:uuid/uuid.dart';

class NoteDetailState extends Equatable {
  const NoteDetailState({
    this.note,
    this.segments = const [],
    this.tags = const [],
    this.allTags = const [],
    this.position = Duration.zero,
    this.playing = false,
    this.audioDuration,
    this.loading = true,
    this.deleted = false,
  });

  final NoteRow? note;
  final List<SegmentRow> segments;
  final List<TagRow> tags;
  final List<TagRow> allTags;
  final Duration position;
  final bool playing;
  final Duration? audioDuration;
  final bool loading;
  final bool deleted;

  /// Índice do segmento que contém a posição atual do player, ou -1.
  int get activeSegmentIndex {
    final ms = position.inMilliseconds;
    for (var i = 0; i < segments.length; i++) {
      if (ms >= segments[i].startMs && ms < segments[i].endMs) return i;
    }
    return -1;
  }

  NoteDetailState copyWith({
    NoteRow? note,
    List<SegmentRow>? segments,
    List<TagRow>? tags,
    List<TagRow>? allTags,
    Duration? position,
    bool? playing,
    Duration? audioDuration,
    bool? loading,
    bool? deleted,
  }) => NoteDetailState(
    note: note ?? this.note,
    segments: segments ?? this.segments,
    tags: tags ?? this.tags,
    allTags: allTags ?? this.allTags,
    position: position ?? this.position,
    playing: playing ?? this.playing,
    audioDuration: audioDuration ?? this.audioDuration,
    loading: loading ?? this.loading,
    deleted: deleted ?? this.deleted,
  );

  @override
  List<Object?> get props => [
    note,
    segments,
    tags,
    allTags,
    position,
    playing,
    audioDuration,
    loading,
    deleted,
  ];
}

/// Detalhe de uma nota: player sincronizado, edição de título/tags e export.
class NoteDetailCubit extends Cubit<NoteDetailState> {
  NoteDetailCubit({
    required String noteId,
    required NoteRepository repository,
    required AudioPlayerController player,
    Uuid? uuid,
  }) : _noteId = noteId,
       _repository = repository,
       _player = player,
       _uuid = uuid ?? const Uuid(),
       super(const NoteDetailState()) {
    _noteSub = _repository.watchNote(noteId).listen(_onNote);
    _segmentsSub = _repository
        .watchSegments(noteId)
        .listen((s) => emit(state.copyWith(segments: s)));
    _tagsSub = _repository
        .watchNoteTags(noteId)
        .listen((t) => emit(state.copyWith(tags: t)));
    _allTagsSub = _repository.watchTags().listen(
      (t) => emit(state.copyWith(allTags: t)),
    );
    _positionSub = _player.positionStream.listen(
      (p) => emit(state.copyWith(position: p)),
    );
    _playingSub = _player.playingStream.listen(
      (p) => emit(state.copyWith(playing: p)),
    );
  }

  final String _noteId;
  final NoteRepository _repository;
  final AudioPlayerController _player;
  final Uuid _uuid;

  StreamSubscription<NoteRow?>? _noteSub;
  StreamSubscription<List<SegmentRow>>? _segmentsSub;
  StreamSubscription<List<TagRow>>? _tagsSub;
  StreamSubscription<List<TagRow>>? _allTagsSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  String? _loadedPath;

  Future<void> _onNote(NoteRow? note) async {
    emit(state.copyWith(note: note, loading: false));
    final path = note?.playbackPath;
    if (note != null && path != null && path != _loadedPath) {
      _loadedPath = path;
      if (File(path).existsSync()) {
        try {
          final duration = await _player.load(path);
          if (!isClosed) emit(state.copyWith(audioDuration: duration));
        } on Object catch (e, st) {
          await AppLogger.error(e, st, reason: 'load_audio', category: 'notes');
        }
      }
    }
  }

  Future<void> togglePlay() => state.playing ? _player.pause() : _player.play();

  Future<void> seek(Duration position) => _player.seek(position);

  /// Pula o player para o início do segmento e começa a tocar.
  Future<void> seekToSegment(SegmentRow segment) async {
    await _player.seek(Duration(milliseconds: segment.startMs));
    await _player.play();
  }

  Future<void> updateTitle(String title) =>
      _repository.updateTitle(_noteId, title.trim());

  Future<void> togglePin() async {
    final pinned = state.note?.pinned ?? false;
    await _repository.setPinned(_noteId, pinned: !pinned);
  }

  Future<void> addTag(String tagId) => _repository.addTagToNote(_noteId, tagId);

  Future<void> removeTag(String tagId) =>
      _repository.removeTagFromNote(_noteId, tagId);

  Future<void> createTagAndAttach(String name, {String? emoji}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = _uuid.v4();
    await _repository.upsertTag(
      TagsCompanion.insert(id: id, name: trimmed, emoji: Value(emoji)),
    );
    await _repository.addTagToNote(_noteId, id);
  }

  Future<void> delete() async {
    await _player.pause();
    await _repository.deleteNote(_noteId);
    _deleteFilesQuietly();
    if (!isClosed) emit(state.copyWith(deleted: true));
  }

  void _deleteFilesQuietly() {
    final note = state.note;
    if (note == null) return;
    for (final path in [
      note.playbackPath,
      note.micWavPath,
      note.systemWavPath,
    ]) {
      if (path == null) continue;
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  @override
  Future<void> close() async {
    await _noteSub?.cancel();
    await _segmentsSub?.cancel();
    await _tagsSub?.cancel();
    await _allTagsSub?.cancel();
    await _positionSub?.cancel();
    await _playingSub?.cancel();
    await _player.dispose();
    return super.close();
  }
}
