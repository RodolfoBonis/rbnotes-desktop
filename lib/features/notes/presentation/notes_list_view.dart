import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/notes/presentation/notes_list_cubit.dart';
import 'package:rbnotes/features/recording/presentation/recording_panel.dart';
import 'package:rbnotes/features/transcription/data/transcription_queue.dart';

/// Lista lateral: gravação, busca, filtro por tag e notas (fixadas primeiro,
/// agrupadas por dia). O progresso da transcrição aparece em cada nota.
class NotesListView extends StatelessWidget {
  const NotesListView({
    required this.selectedId,
    required this.onSelect,
    required this.tags,
    super.key,
  });

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final List<TagRow> tags;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return BlocBuilder<NotesListCubit, NotesListState>(
      builder: (context, state) {
        final cubit = context.read<NotesListCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const RecordingPanel(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FormaSpacing.base,
                FormaSpacing.md,
                FormaSpacing.base,
                FormaSpacing.sm,
              ),
              child: FormaTextField(
                hint: 'Buscar notas',
                prefix: const Icon(Icons.search_rounded, size: 18),
                onChanged: cubit.setQuery,
              ),
            ),
            if (tags.isNotEmpty)
              _TagFilterBar(
                tags: tags,
                selectedId: state.tagFilterId,
                onSelect: cubit.setTagFilter,
              ),
            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(context, state, c),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotesListState state,
    FormaThemeExtension c,
  ) {
    if (state.isSearching) {
      final results = state.searchResults ?? const [];
      if (results.isEmpty) {
        return const Center(
          child: FormaEmptyState(
            icon: Icons.search_off_rounded,
            title: 'Nada encontrado',
            message: 'Tente outros termos.',
            compact: true,
          ),
        );
      }
      return ListView.builder(
        itemCount: results.length,
        itemBuilder: (context, i) {
          final hit = results[i];
          return _NoteTile(
            note: hit.note,
            tags: const [],
            snippet: hit.snippet,
            selected: hit.note.id == selectedId,
            onTap: () => onSelect(hit.note.id),
          );
        },
      );
    }

    if (state.notes.isEmpty) {
      return const Center(
        child: FormaEmptyState(
          icon: Icons.graphic_eq_rounded,
          title: 'Sem notas ainda',
          message: 'Toque no microfone para gravar a primeira.',
          compact: true,
        ),
      );
    }

    return _GroupedList(
      notes: state.notes,
      progress: state.progress,
      selectedId: selectedId,
      onSelect: onSelect,
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.notes,
    required this.progress,
    required this.selectedId,
    required this.onSelect,
  });

  final List<NoteListItem> notes;
  final Map<String, TranscriptionProgress> progress;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final pinned = notes.where((n) => n.note.pinned).toList();
    final rest = notes.where((n) => !n.note.pinned).toList();

    final sections = <Widget>[];
    void addGroup(String label, List<NoteListItem> items) {
      if (items.isEmpty) return;
      sections
        ..add(_GroupHeader(label: label))
        ..addAll(
          items.map(
            (item) => _NoteTile(
              note: item.note,
              tags: item.tags,
              progress: progress[item.note.id],
              selected: item.note.id == selectedId,
              onTap: () => onSelect(item.note.id),
              onRetry: () => context
                  .read<NotesListCubit>()
                  .retryTranscription(item.note.id),
            ),
          ),
        );
    }

    addGroup('Fixadas', pinned);

    String? currentDay;
    final dayItems = <NoteListItem>[];
    for (final item in rest) {
      final label = Formatters.dayLabel(item.note.createdAt);
      if (label != currentDay) {
        if (currentDay != null) addGroup(currentDay, dayItems);
        currentDay = label;
        dayItems.clear();
      }
      dayItems.add(item);
    }
    if (currentDay != null) addGroup(currentDay, dayItems);

    return ListView(children: sections);
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FormaSpacing.base,
        FormaSpacing.base,
        FormaSpacing.base,
        FormaSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: context.formaTypography.overline10.copyWith(color: c.textHint),
      ),
    );
  }
}

class _TagFilterBar extends StatelessWidget {
  const _TagFilterBar({
    required this.tags,
    required this.selectedId,
    required this.onSelect,
  });

  final List<TagRow> tags;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FormaSpacing.base),
        children: [
          _FilterChip(
            label: 'Todas',
            selected: selectedId == null,
            onTap: () => onSelect(null),
          ),
          for (final tag in tags)
            _FilterChip(
              label: '${tag.emoji == null ? '' : '${tag.emoji} '}${tag.name}',
              selected: selectedId == tag.id,
              onTap: () => onSelect(tag.id),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return Padding(
      padding: const EdgeInsets.only(right: FormaSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FormaSpacing.md,
            vertical: FormaSpacing.xs,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.primarySurface : c.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? c.primaryColor : c.border,
            ),
          ),
          child: Text(
            label,
            style: context.formaTypography.caption12.copyWith(
              color: selected ? c.primaryColor : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.note,
    required this.tags,
    required this.selected,
    required this.onTap,
    this.progress,
    this.snippet,
    this.onRetry,
  });

  final NoteRow note;
  final List<TagRow> tags;
  final bool selected;
  final VoidCallback onTap;
  final TranscriptionProgress? progress;
  final String? snippet;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final title = note.title.trim().isEmpty ? 'Sem título' : note.title;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FormaSpacing.base,
          vertical: FormaSpacing.sm,
        ),
        color: selected ? c.primarySurface : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (note.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: FormaSpacing.xs),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 13,
                      color: c.textHint,
                    ),
                  ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.formaTypography.body14Medium.copyWith(
                      color: c.textPrimary,
                    ),
                  ),
                ),
                if (note.source == NoteSource.dictation)
                  Icon(
                    Icons.keyboard_voice_outlined,
                    size: 14,
                    color: c.textHint,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  Formatters.time(note.createdAt),
                  style: context.formaTypography.caption12.copyWith(
                    color: c.textHint,
                  ),
                ),
                if (note.durationMs > 0) ...[
                  Text(
                    '  ·  ${Formatters.durationMs(note.durationMs)}',
                    style: context.formaTypography.caption12.copyWith(
                      color: c.textHint,
                    ),
                  ),
                ],
                const Spacer(),
                _StatusHint(
                  status: note.status,
                  progress: progress,
                  colors: c,
                  onRetry: onRetry,
                ),
              ],
            ),
            if (snippet != null && snippet!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                snippet!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.formaTypography.caption12.copyWith(
                  color: c.textMuted,
                ),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: FormaSpacing.xs),
              Wrap(
                spacing: FormaSpacing.xs,
                runSpacing: FormaSpacing.xs,
                children: [
                  for (final tag in tags) FormaChip(label: tag.displayLabel),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusHint extends StatelessWidget {
  const _StatusHint({
    required this.status,
    required this.progress,
    required this.colors,
    this.onRetry,
  });

  final NoteStatus status;
  final TranscriptionProgress? progress;
  final FormaThemeExtension colors;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (progress != null && !progress!.done) {
      return SizedBox(
        width: 70,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress!.progress == 0 ? null : progress!.progress,
              ),
            ),
            const SizedBox(width: FormaSpacing.xs),
            Text(
              'transcr.',
              style: context.formaTypography.overline10.copyWith(
                color: colors.textHint,
              ),
            ),
          ],
        ),
      );
    }
    return switch (status) {
      NoteStatus.transcribing => Text(
        'na fila',
        style: context.formaTypography.overline10.copyWith(
          color: colors.textHint,
        ),
      ),
      NoteStatus.failed => Tooltip(
        message: 'Falhou — tentar de novo',
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.refresh_rounded,
              size: 16,
              color: colors.errorColor,
            ),
          ),
        ),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
