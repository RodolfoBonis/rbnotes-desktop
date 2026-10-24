import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/traffic_lights.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/data/ai_activity.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/library/presentation/sidebar_icons.dart';

/// Sidebar translúcida (228px): biblioteca, pastas, coleções, status e perfil.
class Sidebar extends StatelessWidget {
  const Sidebar({
    required this.userName,
    required this.userInitials,
    required this.userEmail,
    required this.modelLabel,
    required this.onOpenNewCollection,
    required this.onOpenSettings,
    required this.onToggleAppearance,
    this.aiStatus,
    super.key,
  });

  final String userName;
  final String userInitials;
  final String userEmail;
  final String modelLabel;
  final VoidCallback onOpenNewCollection;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleAppearance;

  /// Fase da IA (real): muda o card "Claude" para refletir fila/erro/limite.
  /// Null = local-first (sempre "pronto").
  final Stream<AiPhase>? aiStatus;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final now = DateTime.now();
    return Container(
      width: 228,
      decoration: BoxDecoration(
        color: rb.side,
        border: Border(right: BorderSide(color: rb.hairline, width: 0.5)),
      ),
      child: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          final cubit = context.read<LibraryCubit>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                height: 52,
                child: Padding(
                  padding: EdgeInsets.only(left: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TrafficLights(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Rb',
                      style: context.serif(size: 22, letterSpacing: -0.4),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Notes',
                      style: context.bodyText(
                        size: 15,
                        weight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    _LibRow(
                      icon: SidebarIcon.allNotes,
                      label: 'Todas as notas',
                      count: state.allCount,
                      selected: state.section == LibrarySection.all,
                      onTap: () => cubit.selectSection(LibrarySection.all),
                    ),
                    _LibRow(
                      icon: SidebarIcon.favorites,
                      label: 'Favoritas',
                      count: state.favCount,
                      selected: state.section == LibrarySection.fav,
                      onTap: () => cubit.selectSection(LibrarySection.fav),
                    ),
                    _LibRow(
                      icon: SidebarIcon.diary,
                      label: 'Diário',
                      count: state.diaryCount,
                      selected: state.section == LibrarySection.diary,
                      onTap: () => cubit.selectSection(LibrarySection.diary),
                    ),
                    const _SectionLabel('Pastas'),
                    for (final f in state.folders.where((f) => !f.hidden))
                      _FolderRow(
                        folder: f,
                        count: state.folderCount(f.id),
                        selected:
                            state.section.kind == SectionKind.folder &&
                            state.section.id == f.id,
                        onTap: () => cubit.selectFolder(f),
                      ),
                    _CollectionsHeader(onAdd: onOpenNewCollection),
                    for (final c in state.collections)
                      _CollectionRow(
                        row: c,
                        count: state.collectionCount(c, now),
                        selected:
                            state.section.kind == SectionKind.collection &&
                            state.section.id == c.id,
                        onTap: () => cubit.selectCollection(c),
                      ),
                  ],
                ),
              ),
              _StatusCard(modelLabel: modelLabel, aiStatus: aiStatus),
              _ProfileRow(
                name: userName,
                email: userEmail,
                initials: userInitials,
                onOpenSettings: onOpenSettings,
                onToggleAppearance: onToggleAppearance,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LibRow extends StatelessWidget {
  const _LibRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final SidebarIcon icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return _RowShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Center(
              child: SidebarGlyph(icon: icon, color: rb.accent),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: context.bodyText(size: 13, weight: FontWeight.w500),
            ),
          ),
          Text(
            '$count',
            style: context.bodyText(size: 12, color: rb.secondary(0.55)),
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final FolderRow folder;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return _RowShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _parseHex(folder.colorHex),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(folder.name, style: context.bodyText(size: 13))),
          Text(
            '$count',
            style: context.bodyText(size: 12, color: rb.secondary(0.55)),
          ),
        ],
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.row,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final CollectionRow row;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final badge = row.kind == 'tasks' && count > 0;
    return _RowShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: Center(
              child: SidebarGlyph(
                icon: SidebarIcon.collection,
                color: rb.accent,
                size: 12,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              row.label,
              overflow: TextOverflow.ellipsis,
              style: context.bodyText(size: 13),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 18),
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge ? rb.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$count',
              style: context.bodyText(
                size: 11.5,
                weight: FontWeight.w600,
                color: badge ? Colors.white : rb.secondary(0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.child,
    required this.selected,
    required this.onTap,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? rb.onSurface(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
      child: Text(
        text,
        style: context.bodyText(
          size: 11,
          weight: FontWeight.w600,
          color: context.rb.secondary(0.5),
        ),
      ),
    );
  }
}

class _CollectionsHeader extends StatelessWidget {
  const _CollectionsHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Coleções inteligentes',
              style: context.bodyText(
                size: 11,
                weight: FontWeight.w600,
                color: rb.secondary(0.5),
              ),
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 20,
              height: 20,
              child: Center(
                child: Text(
                  '+',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1,
                    color: rb.secondary(0.7),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.modelLabel, this.aiStatus});
  final String modelLabel;
  final Stream<AiPhase>? aiStatus;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: rb.sideCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: rb.onSurface(0.08), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusLine(
            context,
            title: 'Whisper $modelLabel',
            subtitle: 'Local · Neural Engine · 1,6 GB',
          ),
          const SizedBox(height: 8),
          if (aiStatus == null)
            _statusLine(
              context,
              title: 'Claude',
              subtitle: 'Só recebe o texto, nunca o áudio',
            )
          else
            StreamBuilder<AiPhase>(
              stream: aiStatus,
              initialData: AiPhase.idle,
              builder: (context, snap) {
                final phase = snap.data ?? AiPhase.idle;
                final (subtitle, dot) = _claudeStatus(phase);
                return _statusLine(
                  context,
                  title: 'Claude',
                  subtitle: subtitle,
                  dotColor: dot,
                );
              },
            ),
        ],
      ),
    );
  }

  static (String, Color) _claudeStatus(AiPhase phase) => switch (phase) {
    AiPhase.idle => (
      'Só recebe o texto, nunca o áudio',
      RbTokens.statusGreen,
    ),
    AiPhase.queued => ('Na fila…', const Color(0xFFB7791F)),
    AiPhase.streaming => ('Processando…', const Color(0xFFB7791F)),
    AiPhase.error => ('Erro na IA', const Color(0xFFD70015)),
    AiPhase.dailyLimit => ('Limite diário atingido', const Color(0xFFD70015)),
  };

  Widget _statusLine(
    BuildContext context, {
    required String title,
    required String subtitle,
    Color dotColor = RbTokens.statusGreen,
  }) {
    final rb = context.rb;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 3),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.bodyText(size: 12, weight: FontWeight.w600),
              ),
              Text(
                subtitle,
                style: context.bodyText(size: 11, color: rb.secondary(0.6)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.name,
    required this.email,
    required this.initials,
    required this.onOpenSettings,
    required this.onToggleAppearance,
  });

  final String name;
  final String email;
  final String initials;
  final VoidCallback onOpenSettings;
  final VoidCallback onToggleAppearance;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: rb.ink, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: context.bodyText(
                size: 10.5,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: context.bodyText(size: 12.5, weight: FontWeight.w600),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyText(
                      size: 11,
                      color: rb.secondary(0.6),
                    ),
                  ),
              ],
            ),
          ),
          _IconButton(
            onTap: onToggleAppearance,
            icon: Icons.brightness_6_outlined,
          ),
          _IconButton(onTap: onOpenSettings, icon: Icons.settings_outlined),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.onTap, required this.icon});
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 28,
        height: 28,
        child: Icon(icon, size: 16, color: context.rb.secondary(0.75)),
      ),
    );
  }
}

Color _parseHex(String hex) {
  final v = hex.replaceAll('#', '');
  return Color(int.parse('FF$v', radix: 16));
}
