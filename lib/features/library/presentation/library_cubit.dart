import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/enrichment_service.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';
import 'package:rbnotes/features/collections/domain/forgotten_tasks.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';

/// Qual seção da sidebar está selecionada.
enum SectionKind { all, fav, diary, folder, collection }

/// Painel principal: nota, tarefas esquecidas ou diário.
enum MainView { note, tasks, diary }

/// Seção selecionada (id + rótulo).
class LibrarySection extends Equatable {
  const LibrarySection({required this.kind, required this.id, this.label});

  static const all = LibrarySection(
    kind: SectionKind.all,
    id: 'all',
    label: 'Todas as notas',
  );
  static const fav = LibrarySection(
    kind: SectionKind.fav,
    id: 'fav',
    label: 'Favoritas',
  );
  static const diary = LibrarySection(
    kind: SectionKind.diary,
    id: 'diario',
    label: 'Diário',
  );

  final SectionKind kind;
  final String id;
  final String? label;

  @override
  List<Object?> get props => [kind, id, label];
}

class LibraryState extends Equatable {
  const LibraryState({
    this.folders = const [],
    this.collections = const [],
    this.notes = const [],
    this.actions = const [],
    this.aiByNote = const {},
    this.section = LibrarySection.all,
    this.view = MainView.note,
    this.selectedNoteId,
    this.query = '',
    this.loading = true,
  });

  final List<FolderRow> folders;
  final List<CollectionRow> collections;
  final List<NoteRow> notes;
  final List<ActionRow> actions;
  final Map<String, NoteAi> aiByNote;
  final LibrarySection section;
  final MainView view;
  final String? selectedNoteId;
  final String query;
  final bool loading;

  LibraryState copyWith({
    List<FolderRow>? folders,
    List<CollectionRow>? collections,
    List<NoteRow>? notes,
    List<ActionRow>? actions,
    Map<String, NoteAi>? aiByNote,
    LibrarySection? section,
    MainView? view,
    String? selectedNoteId,
    bool clearSelection = false,
    String? query,
    bool? loading,
  }) => LibraryState(
    folders: folders ?? this.folders,
    collections: collections ?? this.collections,
    notes: notes ?? this.notes,
    actions: actions ?? this.actions,
    aiByNote: aiByNote ?? this.aiByNote,
    section: section ?? this.section,
    view: view ?? this.view,
    selectedNoteId: clearSelection
        ? null
        : (selectedNoteId ?? this.selectedNoteId),
    query: query ?? this.query,
    loading: loading ?? this.loading,
  );

  @override
  List<Object?> get props => [
    folders,
    collections,
    notes,
    actions,
    aiByNote,
    section,
    view,
    selectedNoteId,
    query,
    loading,
  ];

  // ---------- derivados ----------

  /// Ações abertas por nota (sem conclusão, descarte ou snooze ativo).
  bool _hasOpenActions(String noteId, DateTime now) => actions.any(
    (a) =>
        a.noteId == noteId &&
        !a.done &&
        !a.dismissed &&
        (a.snoozedUntil == null || !a.snoozedUntil!.isAfter(now)),
  );

  int _speakerCount(NoteRow n) => EnrichmentService.decodeSpeakers(
    n.speakersJson,
  ).length;

  /// Notas visíveis na seção atual (sem busca).
  List<NoteRow> notesForSection(DateTime now) {
    final nonDiary = notes.where((n) => n.kind != NoteKind.diary);
    switch (section.kind) {
      case SectionKind.all:
        return nonDiary.toList();
      case SectionKind.fav:
        return notes.where((n) => n.favorite).toList();
      case SectionKind.diary:
        return notes.where((n) => n.kind == NoteKind.diary).toList();
      case SectionKind.folder:
        return notes.where((n) => n.folderId == section.id).toList();
      case SectionKind.collection:
        return _collectionNotes(now);
    }
  }

  List<NoteRow> _collectionNotes(DateTime now) {
    final row = collections.firstWhere(
      (c) => c.id == section.id,
      orElse: () => collections.first,
    );
    if (row.kind == 'tasks') {
      final ids = forgottenTasks(
        notes: _taskInputs(),
        now: now,
      ).map((t) => t.noteId).toSet();
      return notes.where((n) => ids.contains(n.id)).toList();
    }
    final rule = CollectionRule.decode(row.ruleJson);
    return notes
        .where((n) => n.kind != NoteKind.diary)
        .where((n) => rule.matches(_candidate(n, now)))
        .toList();
  }

  CollectionCandidate _candidate(NoteRow n, DateTime now) {
    final ai = aiByNote[n.id];
    final text = [
      n.title,
      ai?.tldr ?? '',
      EnrichmentService.decodeSpeakers(n.speakersJson).join(' '),
    ].join(' ');
    return CollectionCandidate(
      folderId: n.folderId,
      speakerCount: _speakerCount(n),
      hasOpenActions: _hasOpenActions(n.id, now),
      searchableText: text,
    );
  }

  List<TaskNoteInput> _taskInputs() => notes
      .where((n) => n.kind != NoteKind.diary)
      .map(
        (n) => TaskNoteInput(
          noteId: n.id,
          title: n.title,
          createdAt: n.createdAt,
          isDiary: false,
          actions: actions
              .where((a) => a.noteId == n.id)
              .map(
                (a) => TaskActionInput(
                  id: a.id,
                  text: a.content,
                  owner: a.owner,
                  done: a.done,
                  dismissed: a.dismissed,
                  snoozedUntil: a.snoozedUntil,
                ),
              )
              .toList(),
        ),
      )
      .toList();

  /// Tarefas esquecidas (para a coleção e a tela dedicada).
  List<ForgottenTask> forgotten(DateTime now) =>
      forgottenTasks(notes: _taskInputs(), now: now);

  /// Contagem exibida numa coleção.
  int collectionCount(CollectionRow row, DateTime now) {
    if (row.kind == 'tasks') return forgotten(now).length;
    final rule = CollectionRule.decode(row.ruleJson);
    return notes
        .where((n) => n.kind != NoteKind.diary)
        .where((n) => rule.matches(_candidate(n, now)))
        .length;
  }

  int folderCount(String folderId) =>
      notes.where((n) => n.folderId == folderId).length;

  int get allCount => notes.where((n) => n.kind != NoteKind.diary).length;
  int get favCount => notes.where((n) => n.favorite).length;
  int get diaryCount => notes.where((n) => n.kind == NoteKind.diary).length;
}

/// Alimenta a sidebar e a lista a partir dos repositórios e guarda a seleção.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({
    required NoteRepository notes,
    required NoteAiRepository noteAi,
    required LibraryRepository library,
  }) : _notes = notes,
       _noteAi = noteAi,
       _library = library,
       super(const LibraryState()) {
    _folders = _library.watchFolders().listen((v) {
      emit(state.copyWith(folders: v, loading: false));
    });
    _collections = _library.watchCollections().listen((v) {
      emit(state.copyWith(collections: v));
    });
    _notesSub = _notes.watchAllNotes().listen((v) {
      emit(state.copyWith(notes: v, loading: false));
      _ensureSelection();
    });
    _actionsSub = _noteAi.watchAllActions().listen((v) {
      emit(state.copyWith(actions: v));
    });
    _aiSub = _noteAi.watchAllNoteAi().listen((v) {
      emit(state.copyWith(aiByNote: v));
    });
  }

  final NoteRepository _notes;
  final NoteAiRepository _noteAi;
  final LibraryRepository _library;

  StreamSubscription<List<FolderRow>>? _folders;
  StreamSubscription<List<CollectionRow>>? _collections;
  StreamSubscription<List<NoteRow>>? _notesSub;
  StreamSubscription<List<ActionRow>>? _actionsSub;
  StreamSubscription<Map<String, NoteAi>>? _aiSub;

  void _ensureSelection() {
    if (state.selectedNoteId != null &&
        state.notes.any((n) => n.id == state.selectedNoteId)) {
      return;
    }
    final visible = state.notesForSection(DateTime.now());
    if (visible.isNotEmpty && state.view == MainView.note) {
      emit(state.copyWith(selectedNoteId: visible.first.id));
    }
  }

  void selectSection(LibrarySection section) {
    final view = switch (section.kind) {
      SectionKind.diary => MainView.diary,
      SectionKind.collection =>
        section.id == 'c-forgot' ? MainView.tasks : MainView.note,
      _ => MainView.note,
    };
    emit(state.copyWith(section: section, view: view, query: ''));
    if (view == MainView.note) {
      final visible = state.notesForSection(DateTime.now());
      emit(
        state.copyWith(
          selectedNoteId: visible.isEmpty ? null : visible.first.id,
          clearSelection: visible.isEmpty,
        ),
      );
    }
  }

  void selectCollection(CollectionRow row) => selectSection(
    LibrarySection(
      kind: SectionKind.collection,
      id: row.id,
      label: row.label,
    ),
  );

  void selectFolder(FolderRow folder) => selectSection(
    LibrarySection(
      kind: SectionKind.folder,
      id: folder.id,
      label: folder.name,
    ),
  );

  void selectNote(String noteId) =>
      emit(state.copyWith(selectedNoteId: noteId, view: MainView.note));

  /// Abre o painel de visão geral (tarefas/diário) da seção atual.
  void openOverview() {
    final view = state.section.kind == SectionKind.diary
        ? MainView.diary
        : MainView.tasks;
    emit(state.copyWith(view: view));
  }

  void setQuery(String query) => emit(state.copyWith(query: query));

  @override
  Future<void> close() async {
    await _folders?.cancel();
    await _collections?.cancel();
    await _notesSub?.cancel();
    await _actionsSub?.cancel();
    await _aiSub?.cancel();
    return super.close();
  }
}
