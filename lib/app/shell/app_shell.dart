import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/app/shell/overlays.dart';
import 'package:rbnotes/app/shell/recovery_dialog.dart';
import 'package:rbnotes/app/shell/shell_overlay_cubit.dart';
import 'package:rbnotes/app/shell/tray_controller.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';
import 'package:rbnotes/features/collections/domain/forgotten_tasks.dart';
import 'package:rbnotes/features/collections/presentation/tasks_pane.dart';
import 'package:rbnotes/features/diary/presentation/diary_cubit.dart';
import 'package:rbnotes/features/diary/presentation/diary_pane.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/library/presentation/note_list.dart';
import 'package:rbnotes/features/library/presentation/sidebar.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_pane.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_hud.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';
import 'package:uuid/uuid.dart';

/// Casca de 3 colunas (sidebar, lista, detalhe) com overlays, HUDs e atalhos.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final TrayController _tray;
  final _focusNode = FocusNode();
  StreamSubscription<String>? _noticesSub;
  StreamSubscription<CreatedNote>? _createdSub;

  @override
  void initState() {
    super.initState();
    _tray = TrayController(
      recording: context.read<RecordingCubit>(),
      onOpen: () async {},
    );
    unawaited(_tray.init());

    // Avisos do detalhe (ex.: correção de palavra) viram toast.
    _noticesSub = context.read<NoteViewCubit>().notices.listen((msg) {
      if (mounted) context.read<ShellOverlayCubit>().showToast(msg);
    });

    // Nota recém-gravada: seleciona e fecha o HUD.
    _createdSub = context.read<RecordingCubit>().createdNotes.listen((n) {
      if (!mounted) return;
      context.read<LibraryCubit>()
        ..selectSection(
          n.kind == NoteKind.diary ? LibrarySection.diary : LibrarySection.all,
        )
        ..selectNote(n.id);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _runRecovery());
  }

  Future<void> _runRecovery() async {
    final cubit = RecoveryCubit(
      native: di(),
      repository: di(),
      queue: di(),
      paths: di(),
    );
    await cubit.scan();
    if (cubit.state.recoverable.isNotEmpty && mounted) {
      await showRecoveryDialog(context, cubit);
    }
    await cubit.close();
  }

  @override
  void dispose() {
    unawaited(_noticesSub?.cancel());
    unawaited(_createdSub?.cancel());
    _tray.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final overlay = context.read<ShellOverlayCubit>();
    final key = event.logicalKey;

    if (meta && key == LogicalKeyboardKey.comma) {
      overlay.toggleSettings();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      return overlay.closeTop()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (overlay.state.settingsOpen) return KeyEventResult.ignored;
    if (meta && key == LogicalKeyboardKey.keyK) {
      overlay.toggleAsk();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyR) {
      unawaited(context.read<RecordingCubit>().start());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space &&
        !context.read<RecordingCubit>().state.isActive) {
      unawaited(context.read<NoteViewCubit>().togglePlay());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: rb.wallpaper,
        child: Stack(
          children: [
            // Liga a seleção da lista ao detalhe e carrega o diário.
            BlocListener<LibraryCubit, LibraryState>(
              listenWhen: (a, b) =>
                  a.selectedNoteId != b.selectedNoteId || a.view != b.view,
              listener: (context, state) {
                if (state.selectedNoteId != null) {
                  unawaited(
                    context.read<NoteViewCubit>().load(state.selectedNoteId!),
                  );
                }
                if (state.view == MainView.diary) {
                  unawaited(context.read<DiaryCubit>().load());
                }
              },
              child: const Row(
                children: [
                  _SidebarColumn(),
                  NoteList(),
                  Expanded(child: _MainColumn()),
                ],
              ),
            ),
            const RecordingHud(),
            const _OverlayLayer(),
          ],
        ),
      ),
    );
  }
}

class _SidebarColumn extends StatelessWidget {
  const _SidebarColumn();

  @override
  Widget build(BuildContext context) {
    final user = di<AuthService>().currentUser;
    final store = di<SettingsStore>();
    final modelLabel = whisperModelInfo[store.model]?.$1 ?? 'Large v3 Turbo';
    return Sidebar(
      userName: user?.name ?? 'Você',
      userInitials: user?.initials ?? 'V',
      modelLabel: modelLabel,
      onOpenNewCollection: context.read<ShellOverlayCubit>().openNewCollection,
      onOpenSettings: context.read<ShellOverlayCubit>().openSettings,
      onToggleAppearance: () => unawaited(
        context.read<ThemeModeCubit>().toggle(Theme.of(context).brightness),
      ),
    );
  }
}

class _MainColumn extends StatelessWidget {
  const _MainColumn();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      buildWhen: (a, b) => a.view != b.view,
      builder: (context, state) {
        switch (state.view) {
          case MainView.tasks:
            return TasksPane(
              onDone: (t) => _taskAction(context, t, _TaskOp.done),
              onSnooze: (t) => _taskAction(context, t, _TaskOp.snooze),
              onDismiss: (t) => _taskAction(context, t, _TaskOp.dismiss),
              onOpenNote: context.read<LibraryCubit>().selectNote,
            );
          case MainView.diary:
            return DiaryPane(
              onRecord: () =>
                  unawaited(context.read<RecordingCubit>().startDiary()),
            );
          case MainView.note:
            return NoteDetailPane(
              onOpenAsk: context.read<ShellOverlayCubit>().openAsk,
              onStartRecording: () =>
                  unawaited(context.read<RecordingCubit>().start()),
              onExport: () {},
              onFixWord: context.read<ShellOverlayCubit>().openFix,
            );
        }
      },
    );
  }

  Future<void> _taskAction(
    BuildContext context,
    ForgottenTask task,
    _TaskOp op,
  ) async {
    final noteAi = di<NoteAiRepository>();
    final overlay = context.read<ShellOverlayCubit>();
    switch (op) {
      case _TaskOp.done:
        await noteAi.setActionDone(task.actionId, done: true);
        overlay.showToast('Tarefa concluída');
      case _TaskOp.snooze:
        await noteAi.snoozeAction(
          task.actionId,
          DateTime.now().add(const Duration(days: 1)),
        );
        overlay.showToast('Vou te lembrar amanhã às 9h');
      case _TaskOp.dismiss:
        await noteAi.dismissAction(task.actionId);
        overlay.showToast('Removida das tarefas esquecidas');
    }
  }
}

enum _TaskOp { done, snooze, dismiss }

class _OverlayLayer extends StatelessWidget {
  const _OverlayLayer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShellOverlayCubit, ShellOverlayState>(
      builder: (context, state) {
        final overlay = context.read<ShellOverlayCubit>();
        final library = context.read<LibraryCubit>();
        return Stack(
          children: [
            if (state.askOpen)
              AskOverlay(
                onClose: overlay.closeAsk,
                colorForNote: (id) => RbTokens.folderColor(
                  library.state.notes
                      .where((n) => n.id == id)
                      .map((n) => n.folderId)
                      .firstOrNull,
                ),
                onOpenSource: (id) {
                  overlay.closeAsk();
                  library
                    ..selectSection(LibrarySection.all)
                    ..selectNote(id);
                },
              ),
            if (state.newCollectionOpen)
              NewCollectionModal(
                onClose: overlay.closeNewCollection,
                onCreate: (desc) => _createCollection(context, desc),
              ),
            if (state.fixOpen) _FixModal(word: state.fixWord!),
            if (state.settingsOpen) const _SettingsLayer(),
            if (state.toast != null) ShellToast(message: state.toast!),
          ],
        );
      },
    );
  }

  Future<void> _createCollection(BuildContext context, String desc) async {
    if (desc.trim().isEmpty) return;
    final overlay = context.read<ShellOverlayCubit>();
    final library = context.read<LibraryCubit>();
    final ai = di<LibraryRepository>();
    // Gera a regra localmente (o FakeAiClient usa a mesma lógica).
    final result = CollectionRuleResult.fromDescription(desc);
    final id = 'c${DateTime.now().millisecondsSinceEpoch}';
    await ai.upsertCollection(
      CollectionsCompanion.insert(
        id: id,
        label: result.label,
        ruleText: result.ruleText,
        ruleJson: result.rule.encode(),
        sortOrder: const Value(100),
        updatedAt: DateTime.now(),
      ),
    );
    overlay
      ..closeNewCollection()
      ..showToast('Coleção criada. Ela se atualiza sozinha.');
    // Seleciona a nova coleção quando aparecer.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final row = library.state.collections.where((c) => c.id == id).firstOrNull;
    if (row != null) library.selectCollection(row);
  }
}

class _FixModal extends StatelessWidget {
  const _FixModal({required this.word});
  final String word;

  @override
  Widget build(BuildContext context) {
    final repo = di<NoteRepository>();
    final overlay = context.read<ShellOverlayCubit>();
    final noteView = context.read<NoteViewCubit>();
    final vocab = di<VocabularyRepository>();
    return FutureBuilder(
      future: repo.countWord(word),
      builder: (context, snapshot) {
        final count = snapshot.data;
        final occText = count == null
            ? 'Procurando ocorrências…'
            : '${count.occurrences} '
                  '${count.occurrences == 1 ? 'ocorrência' : 'ocorrências'} '
                  'em ${count.notes} '
                  '${count.notes == 1 ? 'nota' : 'notas'}';
        return FixWordModal(
          wrong: word,
          suggestion: word,
          occurrencesText: occText,
          onClose: overlay.closeFix,
          onApply: (to, {required everywhere, required addVocab}) async {
            await noteView.fixWord(
              word,
              to,
              everywhere: everywhere,
              addToVocabulary: addVocab,
            );
            if (addVocab) {
              await vocab.add(const Uuid().v4(), to);
            }
            overlay.closeFix();
          },
        );
      },
    );
  }
}

class _SettingsLayer extends StatelessWidget {
  const _SettingsLayer();

  @override
  Widget build(BuildContext context) {
    final overlay = context.read<ShellOverlayCubit>();
    final user = di<AuthService>().currentUser;
    return SettingsModal(
      store: di<SettingsStore>(),
      native: di(),
      userName: user?.name ?? 'Você',
      userEmail: user?.email ?? '',
      userInitials: user?.initials ?? 'V',
      onClose: overlay.closeSettings,
      onLogout: () async {
        overlay.closeSettings();
        await di<AuthService>().signOut();
      },
    );
  }
}
