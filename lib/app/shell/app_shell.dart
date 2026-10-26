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
import 'package:rbnotes/core/ui/motion.dart';
import 'package:rbnotes/core/windowing/main_window.dart';
import 'package:rbnotes/core/windowing/settings_window_manager.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_cubit.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_screen.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';
import 'package:rbnotes/features/collections/domain/forgotten_tasks.dart';
import 'package:rbnotes/features/collections/presentation/tasks_pane.dart';
import 'package:rbnotes/features/diary/presentation/diary_cubit.dart';
import 'package:rbnotes/features/diary/presentation/diary_gate.dart';
import 'package:rbnotes/features/diary/presentation/diary_pane.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/library/presentation/note_list.dart';
import 'package:rbnotes/features/library/presentation/sidebar.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_actions.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_pane.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/recording/data/meeting_detection_service.dart';
import 'package:rbnotes/features/recording/data/record_note_hotkey_service.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_hud.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/system_settings.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';
import 'package:rbnotes/features/sync/data/sync_service.dart';
import 'package:rbnotes/features/sync/data/sync_status.dart';
import 'package:rbnotes/notifications/notification_coordinator.dart';
import 'package:rbnotes/notifications/notifier.dart';
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
  final _searchFocus = FocusNode();
  StreamSubscription<String>? _noticesSub;
  StreamSubscription<CreatedNote>? _createdSub;
  StreamSubscription<SyncStatus>? _syncStatusSub;
  StreamSubscription<AppLockState>? _lockSub;
  StreamSubscription<MeetingSuggestion>? _meetingSub;
  CreatedNote? _pendingCreated;
  DateTime? _lastRescheduleSyncAt;

  @override
  void initState() {
    super.initState();
    _tray = TrayController(
      recording: context.read<RecordingCubit>(),
      onOpen: () async => di<MainWindowHandle>().activate(),
      settings: di<SettingsStore>(),
    );
    if (!di.isRegistered<TrayController>()) {
      di.registerSingleton<TrayController>(_tray);
    }
    unawaited(_tray.init());

    // Avisos do detalhe (ex.: correção de palavra) viram toast.
    _noticesSub = context.read<NoteViewCubit>().notices.listen((msg) {
      if (mounted) context.read<ShellOverlayCubit>().showToast(msg);
    });

    // Nota recém-gravada: seleciona e fecha o HUD. Se o app está travado
    // (gravação por atalho durante a trava), a nota só aparece após o
    // desbloqueio — guardamos como pendente e revelamos quando destravar.
    _createdSub = context.read<RecordingCubit>().createdNotes.listen((n) {
      if (!mounted) return;
      if (di.isRegistered<SyncService>()) di<SyncService>().requestSync();
      if (context.read<AppLockCubit>().state.locked) {
        _pendingCreated = n;
      } else {
        _revealNote(n);
      }
    });

    // Ao destravar, revela a nota gravada enquanto o app estava bloqueado.
    // Também espelha a trava na detecção de reunião (não sugere travado).
    final meeting = di.isRegistered<MeetingDetectionService>()
        ? di<MeetingDetectionService>()
        : null;
    meeting?.locked = context.read<AppLockCubit>().state.locked;
    _lockSub = context.read<AppLockCubit>().stream.listen((lock) {
      meeting?.locked = lock.locked;
      // A sessão do Diário (M12) expira quando o app trava.
      if (lock.locked && mounted) context.read<DiaryGate>().clear();
      if (!lock.locked && _pendingCreated != null && mounted) {
        _revealNote(_pendingCreated!);
        _pendingCreated = null;
      }
    });

    // Reunião detectada: prompt em foco, notificação fora de foco.
    _meetingSub = meeting?.suggestions.listen(_onMeetingSuggestion);

    // Toque na notificação "Gravar esta reunião?" inicia a gravação.
    if (di.isRegistered<NotificationCoordinator>()) {
      di<NotificationCoordinator>().onStartMeeting = _startMeetingRecording;
    }

    // Atalho global "Gravar nota": liga o disparo ao RecordingCubit (o serviço
    // já registrou o atalho no boot). A janela em foco → HUD interno; sem foco
    // → overlay do notch (decidido dentro de RecordingCubit.start).
    di<RecordNoteHotkeyService>().onTriggered = context
        .read<RecordingCubit>()
        .toggleRecordNote;

    // Roteamento dos toques de notificação + resumo semanal na 1ª abertura.
    if (di.isRegistered<NotificationCoordinator>()) {
      final coord = di<NotificationCoordinator>()
        ..onOpenNote = (id) async {
          if (!mounted || !await _ensureUnlocked() || !mounted) return;
          context.read<LibraryCubit>()
            ..selectSection(LibrarySection.all)
            ..selectNote(id);
        }
        ..onOpenDiary = () async {
          if (!mounted || !await _ensureUnlocked() || !mounted) return;
          context.read<LibraryCubit>().selectSection(LibrarySection.diary);
        }
        ..onOpenWeekly = (_) async {
          if (!mounted || !await _ensureUnlocked() || !mounted) return;
          context.read<ShellOverlayCubit>().openWeekly();
        };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && coord.weeklyDue) {
          context.read<ShellOverlayCubit>().openWeekly();
        }
      });
      // Reagenda após cada sync concluído (tarefas podem ter mudado).
      if (di.isRegistered<SyncService>()) {
        _syncStatusSub = di<SyncService>().status.listen((status) {
          final at = status.lastSyncAt;
          if (status.phase == SyncPhase.idle &&
              at != null &&
              at != _lastRescheduleSyncAt) {
            _lastRescheduleSyncAt = at;
            unawaited(coord.rescheduleAll());
          }
        });
      }
    }

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

  void _revealNote(CreatedNote n) {
    if (!mounted) return;
    context.read<LibraryCubit>()
      ..selectSection(
        n.kind == NoteKind.diary ? LibrarySection.diary : LibrarySection.all,
      )
      ..selectNote(n.id);
  }

  /// Garante o desbloqueio antes de abrir conteúdo a partir de uma notificação.
  Future<bool> _ensureUnlocked() async {
    final lock = context.read<AppLockCubit>();
    if (!lock.state.locked) return true;
    return lock.unlock();
  }

  Future<void> _onMeetingSuggestion(MeetingSuggestion s) async {
    if (!mounted) return;
    final focused = di<MainWindowHandle>().isActive;
    if (!mounted) return;
    if (focused) {
      context.read<ShellOverlayCubit>().openMeetingPrompt(s.app);
    } else if (di.isRegistered<Notifier>()) {
      await di<Notifier>().show(
        id: 'meeting:${s.meetingKey}',
        title: 'Gravar esta reunião?',
        body: 'Detectei uma chamada em ${s.app}.',
        payload: AppNotification(
          kind: NotificationKind.meetingSuggestion,
          date: s.app,
        ),
      );
    }
  }

  /// Inicia a gravação da reunião com o áudio do sistema ligado.
  void _startMeetingRecording() {
    if (!mounted) return;
    context.read<ShellOverlayCubit>().closeMeetingPrompt();
    final rec = context.read<RecordingCubit>()
      ..setCaptureSystemAudio(value: true);
    unawaited(rec.start());
  }

  @override
  void dispose() {
    unawaited(_noticesSub?.cancel());
    unawaited(_lockSub?.cancel());
    unawaited(_meetingSub?.cancel());
    unawaited(_createdSub?.cancel());
    unawaited(_syncStatusSub?.cancel());
    if (di.isRegistered<RecordNoteHotkeyService>()) {
      di<RecordNoteHotkeyService>().onTriggered = null;
    }
    if (di.isRegistered<NotificationCoordinator>()) {
      di<NotificationCoordinator>().onStartMeeting = null;
    }
    _searchFocus.dispose();
    if (di.isRegistered<TrayController>()) {
      final removal = di.unregister<TrayController>();
      if (removal is Future) unawaited(removal);
    }
    _tray.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Travado: nenhum atalho de teclado age atrás da LockScreen (C1). O atalho
    // global "Gravar nota" é tratado pelo RecordNoteHotkeyService, fora daqui.
    if (context.read<AppLockCubit>().state.locked) {
      return KeyEventResult.ignored;
    }
    final meta =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final overlay = context.read<ShellOverlayCubit>();
    final key = event.logicalKey;

    if (meta && key == LogicalKeyboardKey.comma) {
      di<SettingsWindowManager>().openOrFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      return overlay.closeTop()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (meta && key == LogicalKeyboardKey.keyK) {
      overlay.toggleAsk();
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyR) {
      unawaited(context.read<RecordingCubit>().start());
      return KeyEventResult.handled;
    }
    if (meta && key == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space &&
        !context.read<RecordingCubit>().state.isActive) {
      unawaited(context.read<NoteViewCubit>().togglePlay());
      return KeyEventResult.handled;
    }
    // Apagar a nota selecionada (⌫ / ⌘⌫). Não dispara enquanto se digita: um
    // TextField em foco consome o backspace antes de chegar aqui.
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      final library = context.read<LibraryCubit>();
      final lib = library.state;
      final id = lib.selectedNoteId;
      if (id != null && lib.view == MainView.note) {
        NoteRow? note;
        for (final n in lib.notes) {
          if (n.id == id) {
            note = n;
            break;
          }
        }
        if (note != null) {
          unawaited(confirmAndDeleteNote(context, note, library));
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  /// Diálogo "sem acesso ao microfone" com o botão que abre o painel certo.
  Future<void> _showPermissionAlert(
    BuildContext context,
    RecordingAlert alert,
  ) async {
    final cubit = context.read<RecordingCubit>();
    const opener = SystemSettingsOpener();
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Microfone sem acesso'),
        content: Text(alert.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Abrir Ajustes'),
          ),
        ],
      ),
    );
    cubit.dismissAlert();
    if (open ?? false) await opener.openPrivacyPane(alert.permission);
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: rb.wallpaper,
        child: Stack(
          children: [
            // Aviso acionável de permissão de microfone (gravação bloqueada).
            BlocListener<RecordingCubit, RecordingState>(
              listenWhen: (a, b) => a.alert != b.alert && b.alert != null,
              listener: (context, state) =>
                  unawaited(_showPermissionAlert(context, state.alert!)),
              child: const SizedBox.shrink(),
            ),
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
              child: Row(
                children: [
                  const _SidebarColumn(),
                  NoteList(searchFocus: _searchFocus),
                  const Expanded(child: _MainColumn()),
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
      userEmail: user?.email ?? '',
      modelLabel: modelLabel,
      aiStatus: di.isRegistered<AiActivity>() ? di<AiActivity>().stream : null,
      syncStatus: di.isRegistered<SyncService>()
          ? di<SyncService>().status
          : null,
      onOpenNewCollection: context.read<ShellOverlayCubit>().openNewCollection,
      // Resolve lazily (on tap), not during build, so the shell renders even
      // where the manager isn't registered (e.g. some widget tests).
      onOpenSettings: () => di<SettingsWindowManager>().openOrFocus(),
      onOpenWeekly: context.read<ShellOverlayCubit>().openWeekly,
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
              onOpenAsk: context.read<ShellOverlayCubit>().openAsk,
              onStartRecording: () =>
                  unawaited(context.read<RecordingCubit>().start()),
            );
          case MainView.diary:
            return DiaryPane(
              onRecord: () =>
                  unawaited(context.read<RecordingCubit>().startDiary()),
              onOpenAsk: context.read<ShellOverlayCubit>().openAsk,
              onStartRecording: () =>
                  unawaited(context.read<RecordingCubit>().start()),
            );
          case MainView.note:
            return NoteDetailPane(
              onOpenAsk: context.read<ShellOverlayCubit>().openAsk,
              onStartRecording: () =>
                  unawaited(context.read<RecordingCubit>().start()),
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
    final notifier = di<Notifier>();
    final overlay = context.read<ShellOverlayCubit>();
    switch (op) {
      case _TaskOp.done:
        await noteAi.setActionDone(task.actionId, done: true);
        await notifier.cancel('snooze:${task.actionId}');
        overlay.showToast('Tarefa concluída');
      case _TaskOp.snooze:
        final now = DateTime.now();
        final tomorrow9 = DateTime(
          now.year,
          now.month,
          now.day,
          9,
        ).add(const Duration(days: 1));
        await noteAi.snoozeAction(task.actionId, tomorrow9);
        await notifier.schedule(
          id: 'snooze:${task.actionId}',
          when: tomorrow9,
          title: 'Lembrete de tarefa',
          body: task.text,
          payload: AppNotification(
            kind: NotificationKind.taskDue,
            noteId: task.noteId,
          ),
        );
        overlay.showToast('Vou te lembrar amanhã às 9h');
      case _TaskOp.dismiss:
        await noteAi.dismissAction(task.actionId);
        await notifier.cancel('snooze:${task.actionId}');
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
              FadeScaleIn(
                child: AskOverlay(
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
              ),
            if (state.newCollectionOpen)
              FadeScaleIn(
                child: NewCollectionModal(
                  onClose: overlay.closeNewCollection,
                  onCreate: (desc) => _createCollection(context, desc),
                ),
              ),
            if (state.fixOpen)
              FadeScaleIn(child: _FixModal(word: state.fixWord!)),
            if (state.weeklyOpen) const FadeScaleIn(child: _WeeklyLayer()),
            if (state.toast != null) ShellToast(message: state.toast!),
            if (state.meetingApp != null)
              FadeScaleIn(
                child: _MeetingPrompt(
                  app: state.meetingApp!,
                  onRecord: () {
                    overlay.closeMeetingPrompt();
                    context.read<RecordingCubit>().setCaptureSystemAudio(
                      value: true,
                    );
                    unawaited(context.read<RecordingCubit>().start());
                  },
                  onDismiss: overlay.closeMeetingPrompt,
                ),
              ),
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

class _MeetingPrompt extends StatelessWidget {
  const _MeetingPrompt({
    required this.app,
    required this.onRecord,
    required this.onDismiss,
  });

  final String app;
  final VoidCallback onRecord;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 56),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 360,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: rb.bg3,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: rb.onSurface(0.12), width: 0.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Gravar esta reunião?', style: context.serif(size: 16)),
                const SizedBox(height: 4),
                Text(
                  'Detectei uma chamada em $app.',
                  style: context.bodyText(size: 12.5, color: rb.secondary(0.7)),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          'Agora não',
                          style: context.bodyText(
                            size: 12.5,
                            color: rb.secondary(0.75),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onRecord,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: rb.accent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Gravar',
                          style: context.bodyText(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: rb.onAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WeeklyLayer extends StatelessWidget {
  const _WeeklyLayer();

  @override
  Widget build(BuildContext context) {
    final overlay = context.read<ShellOverlayCubit>();
    return BlocProvider(
      create: (_) {
        final cubit = WeeklySummaryCubit(ai: di(), settings: di());
        unawaited(cubit.generate());
        return cubit;
      },
      child: WeeklySummaryScreen(onClose: overlay.closeWeekly),
    );
  }
}
