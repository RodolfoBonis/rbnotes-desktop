import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:rbnotes/app/shell/recovery_dialog.dart';
import 'package:rbnotes/app/shell/tray_controller.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/routing/routes.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/notes/presentation/notes_list_view.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recovery_cubit.dart';
import 'package:window_manager/window_manager.dart';

/// Casca master-detail do app: lista lateral fixa + área de detalhe roteada.
/// Também dispara a recuperação de gravações e mantém o ícone da menu bar.
class AppShell extends StatefulWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final TrayController _tray;

  @override
  void initState() {
    super.initState();
    _tray = TrayController(
      recording: context.read<RecordingCubit>(),
      onOpen: _bringToFront,
    );
    unawaited(_tray.init());
    WidgetsBinding.instance.addPostFrameCallback((_) => _runRecovery());
  }

  @override
  void dispose() {
    _tray.dispose();
    super.dispose();
  }

  Future<void> _bringToFront() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _runRecovery() async {
    final cubit = RecoveryCubit(
      native: di(),
      repository: di(),
      queue: di(),
      paths: di(),
    );
    await cubit.scan();
    if (!mounted || !cubit.state.hasRecoverable) return;
    await showRecoveryDialog(context, cubit);
  }

  String? get _selectedId {
    final location = widget.location;
    if (location.startsWith('/notes/')) {
      return location.substring('/notes/'.length);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.cardBackground,
                border: Border(right: BorderSide(color: c.border)),
              ),
              child: Column(
                children: [
                  _SidebarHeader(onSettings: () => context.go(Routes.settings)),
                  Expanded(
                    child: StreamBuilder<List<TagRow>>(
                      stream: di<NoteRepository>().watchTags(),
                      builder: (context, snapshot) => NotesListView(
                        selectedId: _selectedId,
                        tags: snapshot.data ?? const [],
                        onSelect: (id) => context.go(Routes.note(id)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final mode = context.watch<ThemeModeCubit>().state;
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        FormaSpacing.base,
        FormaSpacing.base,
        FormaSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          Icon(Icons.graphic_eq_rounded, color: c.primaryColor, size: 20),
          const SizedBox(width: FormaSpacing.sm),
          Expanded(
            child: Text('RbNotes', style: context.formaTypography.title16),
          ),
          Tooltip(
            message: 'Alternar tema',
            child: FormaIconButton(
              icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              ),
              onPressed: () => context.read<ThemeModeCubit>().toggle(
                isDark ? Brightness.dark : Brightness.light,
              ),
            ),
          ),
          Tooltip(
            message: 'Configurações',
            child: FormaIconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: onSettings,
            ),
          ),
        ],
      ),
    );
  }
}
