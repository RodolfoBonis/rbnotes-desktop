import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';

class NotesListState extends Equatable {
  const NotesListState({
    this.notes = const [],
    this.query = '',
    this.tagFilterId,
    this.searchResults,
    this.progress = const {},
    this.loading = true,
  });

  final List<NoteListItem> notes;
  final String query;
  final String? tagFilterId;

  /// `null` enquanto não há busca ativa; lista (possivelmente vazia) quando há.
  final List<NoteSearchHit>? searchResults;
  final Map<String, TranscriptionProgress> progress;
  final bool loading;

  bool get isSearching => query.trim().isNotEmpty;

  NotesListState copyWith({
    List<NoteListItem>? notes,
    String? query,
    String? tagFilterId,
    bool clearTagFilter = false,
    List<NoteSearchHit>? searchResults,
    bool clearSearch = false,
    Map<String, TranscriptionProgress>? progress,
    bool? loading,
  }) => NotesListState(
    notes: notes ?? this.notes,
    query: query ?? this.query,
    tagFilterId: clearTagFilter ? null : (tagFilterId ?? this.tagFilterId),
    searchResults: clearSearch ? null : (searchResults ?? this.searchResults),
    progress: progress ?? this.progress,
    loading: loading ?? this.loading,
  );

  @override
  List<Object?> get props => [
    notes,
    query,
    tagFilterId,
    searchResults,
    progress,
    loading,
  ];
}

/// Alimenta a lista lateral: notas (com filtro por tag), busca FTS e o
/// progresso da transcrição em andamento.
class NotesListCubit extends Cubit<NotesListState> {
  NotesListCubit({
    required NoteRepository repository,
    required TranscriptionQueue queue,
  }) : _repository = repository,
       _queue = queue,
       super(const NotesListState()) {
    _notesSub = _repository.watchNotes().listen(_onNotes);
    _progressSub = _queue.progress.listen(_onProgress);
  }

  final NoteRepository _repository;
  final TranscriptionQueue _queue;

  StreamSubscription<List<NoteListItem>>? _notesSub;
  StreamSubscription<TranscriptionProgress>? _progressSub;
  Timer? _debounce;

  void _onNotes(List<NoteListItem> notes) {
    emit(state.copyWith(notes: notes, loading: false));
  }

  void _onProgress(TranscriptionProgress p) {
    final next = Map<String, TranscriptionProgress>.from(state.progress);
    if (p.done) {
      next.remove(p.noteId);
    } else {
      next[p.noteId] = p;
    }
    emit(state.copyWith(progress: next));
  }

  void setTagFilter(String? tagId) {
    if (tagId == state.tagFilterId) return;
    emit(state.copyWith(tagFilterId: tagId, clearTagFilter: tagId == null));
    unawaited(_notesSub?.cancel());
    _notesSub = _repository.watchNotes(tagId: tagId).listen(_onNotes);
  }

  void setQuery(String query) {
    emit(state.copyWith(query: query));
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      emit(state.copyWith(clearSearch: true));
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final results = await _repository.search(query);
      if (isClosed || state.query != query) return;
      emit(state.copyWith(searchResults: results));
    });
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _notesSub?.cancel();
    await _progressSub?.cancel();
    return super.close();
  }
}
