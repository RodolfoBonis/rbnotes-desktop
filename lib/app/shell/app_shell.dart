import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/app/shell/overlays.dart';
import 'package:rbnotes/app/shell/recovery_dialog.dart';
import 'package:rbnotes/app/shell/shell_overlay_cubit.dart';
import 'package:rbnotes/app/shell/tray_controller.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/observability/app_logger.dart';
import 'package:rbnotes/core/paths/app_paths.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/motion.dart';
import 'package:rbnotes/core/ui/task_progress_dialog.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_cubit.dart';
import 'package:rbnotes/features/ai/presentation/weekly_summary_screen.dart';
import 'package:rbnotes/features/auth/data/auth_service.dart';
import 'package:rbnotes/features/collections/domain/collection_rule.dart';
import 'package:rbnotes/features/collections/domain/forgotten_tasks.dart';
import 'package:rbnotes/features/collections/presentation/tasks_pane.dart';
import 'package:rbnotes/features/diary/presentation/diary_cubit.dart';
import 'package:rbnotes/features/diary/presentation/diary_pane.dart';
import 'package:rbnotes/features/dictation/data/dictation_service.dart';
import 'package:rbnotes/features/library/data/library_repository.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/library/presentation/note_list.dart';
import 'package:rbnotes/features/library/presentation/sidebar.dart';
import 'package:rbnotes/features/notes/data/export_service.dart';
import 'package:rbnotes/features/notes/data/note_ai_repository.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/note_actions.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_pane.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/recording/data/record_note_hotkey_service.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_hud.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';
import 'package:rbnotes/features/security/data/biometric_auth.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';
import 'package:rbnotes/features/settings/data/erase_all_service.dart';
import 'package:rbnotes/features/settings/data/local_data_wiper.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';
import 'package:rbnotes/features/settings/data/vocabulary_repository.dart';
import 'package:rbnotes/features/settings/presentation/erase_progress_dialog.dart';
import 'package:rbnotes/features/settings/presentation/settings_modal.dart';
import 'package:rbnotes/features/sync/data/audio_sync.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';
import 'package:rbnotes/features/sync/data/sync_crypto.dart';
import 'package:rbnotes/features/sync/data/sync_local_store.dart';
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
  CreatedNote? _pendingCreated;
  DateTime? _lastRescheduleSyncAt;

  @override
  void initState() {
    super.initState();
    _tray = TrayController(
      recording: context.read<RecordingCubit>(),
      onOpen: () async {},
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
    _lockSub = context.read<AppLockCubit>().stream.listen((lock) {
      if (!lock.locked && _pendingCreated != null && mounted) {
        _revealNote(_pendingCreated!);
        _pendingCreated = null;
      }
    });

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

  @override
  void dispose() {
    unawaited(_noticesSub?.cancel());
    unawaited(_lockSub?.cancel());
    unawaited(_createdSub?.cancel());
    unawaited(_syncStatusSub?.cancel());
    if (di.isRegistered<RecordNoteHotkeyService>()) {
      di<RecordNoteHotkeyService>().onTriggered = null;
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
      onOpenSettings: context.read<ShellOverlayCubit>().openSettings,
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
            if (state.settingsOpen) const FadeScaleIn(child: _SettingsLayer()),
            if (state.weeklyOpen) const FadeScaleIn(child: _WeeklyLayer()),
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
      vocabulary: di(),
      recordNoteHotkey: di(),
      aiUsageClient: di(),
      dictation: di.isRegistered<DictationService>()
          ? di<DictationService>()
          : null,
      noteKeyStore: di(),
      onMenuBarChanged: (enabled) {
        if (di.isRegistered<TrayController>()) {
          unawaited(di<TrayController>().setVisible(enabled: enabled));
        }
      },
      onRecoveryKeyChanged: () {
        if (di.isRegistered<SyncCrypto>()) di<SyncCrypto>().invalidate();
      },
      notifier: di(),
      onNotificationsChanged: () =>
          unawaited(di<NotificationCoordinator>().rescheduleAll()),
      userName: user?.name ?? 'Você',
      userEmail: user?.email ?? '',
      userInitials: user?.initials ?? 'V',
      sync: di.isRegistered<SyncService>() ? di<SyncService>() : null,
      audioQueue: di.isRegistered<AudioUploadQueue>()
          ? di<AudioUploadQueue>()
          : null,
      notes: di<NoteRepository>(),
      onClose: overlay.closeSettings,
      onLogout: ({required wipe}) async {
        overlay.closeSettings();
        if (wipe) await _wipeLocalData();
        await di<AuthService>().signOut();
      },
      onEraseAllData: () => _eraseAllFlow(context),
      onExportAll: () => _exportAllFlow(context),
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

/// "Exportar todas as notas": seletor de destino (file_selector), progresso e
/// Touch ID para as notas bloqueadas (ou deixa-as de fora, com aviso).
Future<void> _exportAllFlow(BuildContext context) async {
  final overlay = context.read<ShellOverlayCubit>();
  final nav = Navigator.of(context, rootNavigator: true);

  final location = await getSaveLocation(
    suggestedName: 'rbnotes-export.zip',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Zip', extensions: ['zip']),
    ],
  );
  final path = location?.path;
  if (path == null) return;

  final message = ValueNotifier<String>('Preparando…');
  final progress = ValueNotifier<double?>(null);
  if (!nav.mounted) {
    message.dispose();
    progress.dispose();
    return;
  }
  unawaited(
    showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => TaskProgressDialog(
        title: 'Exportando notas',
        message: message,
        progress: progress,
      ),
    ),
  );

  final service = ExportService(notes: di<NoteRepository>());
  final biometric = di<BiometricAuth>();
  try {
    final result = await service.exportAll(
      destinationPath: path,
      onProgress: (done, total) {
        message.value = 'Exportando $done de $total…';
        progress.value = total == 0 ? null : done / total;
      },
      unlockLocked: () =>
          biometric.authenticate('Desbloquear notas para exportar'),
    );
    if (nav.canPop()) nav.pop();
    final extra = result.excludedLocked > 0
        ? ' (${result.excludedLocked} bloqueada'
              '${result.excludedLocked == 1 ? '' : 's'} ficaram de fora)'
        : '';
    overlay.showToast('Exportadas ${result.exported} notas$extra.');
  } on Object catch (e, st) {
    if (nav.canPop()) nav.pop();
    await AppLogger.error(e, st, reason: 'export_all', category: 'notes');
    overlay.showToast('Não foi possível exportar as notas.');
  } finally {
    message.dispose();
    progress.dispose();
  }
}

/// Monta o limpador de dados locais a partir do container de DI.
LocalDataWiper _buildWiper() => LocalDataWiper(
  db: di<AppDatabase>(),
  notes: di<NoteRepository>(),
  paths: di<AppPaths>(),
  sync: di.isRegistered<SyncService>() ? di<SyncService>() : null,
  audioQueue: di.isRegistered<AudioUploadQueue>()
      ? di<AudioUploadQueue>()
      : null,
);

/// "Apagar dados locais" do logout: banco, cursor/marca d'água, fila de áudio e
/// os caches de áudio (recordings + audio_cache).
Future<void> _wipeLocalData() => _buildWiper().wipe();

/// "Apagar todos os dados" da aba Privacidade, com progresso. Ordem: tombstones
/// → push → DELETE do áudio na nuvem → limpeza local → reset do cursor. Offline
/// no push: oferece apagar só neste Mac, com aviso.
Future<void> _eraseAllFlow(BuildContext context) async {
  final overlay = context.read<ShellOverlayCubit>();
  final nav = Navigator.of(context, rootNavigator: true);
  final progress = ValueNotifier<EraseProgress?>(null);
  final service = EraseAllService(
    notes: di<NoteRepository>(),
    store: SyncLocalStore(
      di<AppDatabase>(),
      crypto: di.isRegistered<SyncCrypto>() ? di<SyncCrypto>() : null,
    ),
    wiper: _buildWiper(),
    sync: di.isRegistered<SyncService>() ? di<SyncService>() : null,
    audio: di.isRegistered<AudioSync>() ? di<AudioSync>() : null,
  );

  void openProgress() => unawaited(
    showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => EraseProgressDialog(progress: progress),
    ),
  );

  openProgress();
  var result = await service.eraseAll(onProgress: (p) => progress.value = p);

  if (result == EraseResult.offlinePending) {
    if (nav.canPop()) nav.pop();
    if (!nav.mounted) {
      progress.dispose();
      return;
    }
    final goLocal = await showDialog<bool>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        title: const Text('Você está offline'),
        content: const Text(
          'Não consegui falar com o servidor agora. Posso apagar os dados '
          'deste Mac mesmo assim — a exclusão na nuvem acontece quando você '
          'reconectar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Aguardar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: RbTokens.destructive),
            child: const Text('Apagar só neste Mac'),
          ),
        ],
      ),
    );
    if (goLocal ?? false) {
      progress.value = null;
      openProgress();
      result = await service.finishLocalOnly(
        onProgress: (p) => progress.value = p,
      );
    } else {
      progress.dispose();
      overlay
        ..closeSettings()
        ..showToast('Exclusão adiada — você está offline.');
      return;
    }
  }

  if (nav.canPop()) nav.pop();
  progress.dispose();
  overlay.closeSettings();
  if (result == EraseResult.doneLocalOnly) {
    overlay.showToast('Dados apagados neste Mac. A nuvem será limpa depois.');
  }
  await di<AuthService>().signOut();
}
