import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/notes/presentation/note_actions.dart';

/// Lista de notas (304px): título da seção, busca FTS, grupos por data e o
/// item selecionado em laranja.
class NoteList extends StatelessWidget {
  const NoteList({super.key});

  static const _groupOrder = [
    'Hoje',
    'Ontem',
    'Esta semana',
    'Semana passada',
    'Antes',
  ];

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      width: 304,
      decoration: BoxDecoration(
        color: rb.bg2,
        border: Border(right: BorderSide(color: rb.hairline, width: 0.5)),
      ),
      child: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          final cubit = context.read<LibraryCubit>();
          final now = DateTime.now();
          final q = state.query.trim().toLowerCase();
          final visible = state.notesForSection(now).where((n) {
            if (q.isEmpty) return true;
            final tldr = state.aiByNote[n.id]?.tldr ?? '';
            return '${n.title} $tldr'.toLowerCase().contains(q);
          }).toList();

          final grouped = <String, List<NoteRow>>{};
          for (final n in visible) {
            grouped.putIfAbsent(_group(n.createdAt, now), () => []).add(n);
          }

          final hasOverview =
              state.section.kind == SectionKind.diary ||
              state.section.id == 'c-forgot';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(title: _title(state), count: visible.length),
              _SearchBox(
                value: state.query,
                onChanged: cubit.setQuery,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  children: [
                    if (state.section.kind == SectionKind.collection &&
                        state.section.id != 'c-forgot')
                      _RuleBanner(state: state),
                    if (hasOverview)
                      _OverviewCard(
                        label: state.section.kind == SectionKind.diary
                            ? 'Visão do mês'
                            : 'Todas as tarefas esquecidas',
                        meta: state.section.kind == SectionKind.diary
                            ? toBeginningOfSentenceCase(
                                DateFormat.MMMM('pt_BR').format(now),
                              )!
                            : '${state.forgotten(now).length}',
                        active: state.view != MainView.note,
                        onTap: cubit.openOverview,
                      ),
                    for (final g in _groupOrder)
                      if (grouped[g] != null)
                        _Group(
                          label: g,
                          notes: grouped[g]!,
                          state: state,
                          onSelect: cubit.selectNote,
                        ),
                    if (visible.isEmpty && !hasOverview)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
                        child: Text(
                          q.isNotEmpty
                              ? 'Nada encontrado para “${state.query}”.'
                              : 'Nenhuma nota nesta coleção ainda.',
                          textAlign: TextAlign.center,
                          style: context.bodyText(
                            size: 12,
                            height: 1.5,
                            color: rb.secondary(0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _title(LibraryState state) => switch (state.section.kind) {
    SectionKind.all => 'Todas as notas',
    SectionKind.fav => 'Favoritas',
    SectionKind.diary => 'Diário',
    SectionKind.folder || SectionKind.collection => state.section.label ?? '',
  };

  static String _group(DateTime created, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(created.year, created.month, created.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Hoje';
    if (diff == 1) return 'Ontem';
    if (diff < 7) return 'Esta semana';
    if (diff < 14) return 'Semana passada';
    return 'Antes';
  }
}

String noteTimeLabel(DateTime created, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(created.year, created.month, created.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return DateFormat('HH:mm', 'pt_BR').format(created);
  if (diff < 7) {
    final wd = toBeginningOfSentenceCase(
      DateFormat('EEE', 'pt_BR').format(created).replaceAll('.', ''),
    );
    return '$wd, ${DateFormat('HH:mm', 'pt_BR').format(created)}';
  }
  return DateFormat('d MMM', 'pt_BR').format(created).replaceAll('.', '');
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.bodyText(size: 13, weight: FontWeight.w600),
            ),
            Text(
              '$count ${count == 1 ? 'nota' : 'notas'}',
              style: context.bodyText(
                size: 11,
                color: context.rb.secondary(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: rb.controlFill,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: rb.secondary(0.55)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: TextEditingController(text: value)
                  ..selection = TextSelection.collapsed(offset: value.length),
                onChanged: onChanged,
                cursorColor: rb.accent,
                style: context.bodyText(size: 13),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Buscar em notas e transcrições',
                  hintStyle: context.bodyText(
                    size: 13,
                    color: rb.secondary(0.45),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleBanner extends StatelessWidget {
  const _RuleBanner({required this.state});
  final LibraryState state;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final row = state.collections.firstWhere(
      (c) => c.id == state.section.id,
      orElse: () => state.collections.first,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: rb.controlFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Regra criada pelo Claude: ${row.ruleText}',
        style: context.bodyText(
          size: 11.5,
          height: 1.4,
          color: rb.secondary(0.75),
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.label,
    required this.meta,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String meta;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? rb.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: context.bodyText(
                  size: 13,
                  weight: FontWeight.w600,
                  color: active ? Colors.white : rb.text,
                ),
              ),
            ),
            Text(
              meta,
              style: context.bodyText(
                size: 11,
                color: active
                    ? Colors.white.withValues(alpha: 0.85)
                    : rb.secondary(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.notes,
    required this.state,
    required this.onSelect,
  });

  final String label;
  final List<NoteRow> notes;
  final LibraryState state;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
          child: Text(
            label,
            style: context.bodyText(
              size: 11,
              weight: FontWeight.w600,
              color: rb.secondary(0.5),
            ),
          ),
        ),
        for (final n in notes)
          _NoteCard(
            note: n,
            excerpt: state.aiByNote[n.id]?.tldr ?? '',
            selected:
                state.view == MainView.note && n.id == state.selectedNoteId,
            timeLabel: noteTimeLabel(n.createdAt, now),
            onTap: () => onSelect(n.id),
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.excerpt,
    required this.selected,
    required this.timeLabel,
    required this.onTap,
  });

  final NoteRow note;
  final String excerpt;
  final bool selected;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final fg = selected ? Colors.white : rb.text;
    final sub = selected
        ? Colors.white.withValues(alpha: 0.85)
        : rb.secondary(0.62);
    final dot = selected
        ? Colors.white.withValues(alpha: 0.9)
        : RbTokens.folderColor(note.folderId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapDown: (d) {
          onTap(); // seleciona a nota ao abrir o menu de contexto
          unawaited(
            showNoteContextMenu(
              context: context,
              position: d.globalPosition,
              note: note,
              library: context.read<LibraryCubit>(),
            ),
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? rb.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dot,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? 'Sem título' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.bodyText(
                        size: 13,
                        weight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                  _NoteProgressBadge(note: note, selected: selected),
                ],
              ),
              if (excerpt.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 14, top: 3),
                  child: Text(
                    excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyText(size: 12, height: 1.4, color: sub),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 3),
                child: Text(
                  '$timeLabel  ·  ${Formatters.durationMs(note.durationMs)}',
                  style: context.bodyText(size: 11, color: sub),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de processamento no item da lista: gira enquanto transcreve ou
/// gera o resumo (para o progresso aparecer mesmo com o HUD fechado) e mostra
/// um alerta quando a transcrição falhou.
class _NoteProgressBadge extends StatelessWidget {
  const _NoteProgressBadge({required this.note, required this.selected});
  final NoteRow note;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final busy =
        note.status == NoteStatus.transcribing ||
        note.status == NoteStatus.recording ||
        note.aiStatus == AiStatus.pending;
    final failed = note.status == NoteStatus.failed;
    if (!busy && !failed) return const SizedBox.shrink();
    final color = selected ? Colors.white : context.rb.secondary(0.7);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: failed
          ? Icon(
              Icons.error_outline,
              size: 13,
              color: selected ? Colors.white : RbTokens.destructive,
            )
          : SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
    );
  }
}
