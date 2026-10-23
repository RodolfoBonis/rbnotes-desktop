import 'package:flutter/material.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:rbnotes/app/shell/app_shell.dart';
import 'package:rbnotes/core/routing/routes.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_page.dart';
import 'package:rbnotes/features/settings/presentation/settings_page.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (_, _) => const _EmptyDetail(),
          ),
          GoRoute(
            path: Routes.notePattern,
            builder: (_, state) =>
                NoteDetailPage(noteId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: Routes.settings,
            builder: (_, _) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: FormaEmptyState(
        icon: Icons.graphic_eq_rounded,
        title: 'RbNotes',
        message: 'Selecione uma nota ou toque no microfone para gravar.',
      ),
    );
  }
}
