import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_export.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/notes/presentation/audio_player_controller.dart';
import 'package:rbnotes/features/notes/presentation/note_detail_cubit.dart';

/// Detalhe de uma nota: player sincronizado com a transcrição, edição de
/// título, tags e ações (copiar, exportar, apagar).
class NoteDetailPage extends StatelessWidget {
  const NoteDetailPage({required this.noteId, super.key});

  final String noteId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Key força recriar o cubit (e o player) quando troca a nota.
      key: ValueKey(noteId),
      create: (_) => NoteDetailCubit(
        noteId: noteId,
        repository: di(),
        player: di<AudioPlayerController>(),
        queue: di(),
      ),
      child: const _NoteDetailBody(),
    );
  }
}

class _NoteDetailBody extends StatelessWidget {
  const _NoteDetailBody();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<NoteDetailCubit, NoteDetailState>(
      listenWhen: (a, b) => !a.deleted && b.deleted,
      listener: (context, state) {
        // A lista reage sozinha; aqui só limpamos a seleção visual.
      },
      builder: (context, state) {
        final note = state.note;
        if (state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (note == null || state.deleted) {
          return const Center(
            child: FormaEmptyState(
              icon: Icons.notes_rounded,
              title: 'Selecione uma nota',
              message: 'Escolha uma nota na lista ou grave uma nova.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DetailHeader(state: state),
            const Divider(height: 1),
            _PlayerBar(state: state),
            Expanded(child: _Transcript(state: state)),
            _TagsBar(state: state),
          ],
        );
      },
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.state});

  final NoteDetailState state;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final cubit = context.read<NoteDetailCubit>();
    final note = state.note!;
    return Padding(
      padding: const EdgeInsets.all(FormaSpacing.base),
      child: Row(
        children: [
          Expanded(
            child: Text(
              note.title.trim().isEmpty ? 'Sem título' : note.title,
              style: context.formaTypography.h3,
            ),
          ),
          Tooltip(
            message: 'Renomear',
            child: FormaIconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editTitle(context, cubit, note.title),
            ),
          ),
          Tooltip(
            message: note.pinned ? 'Desafixar' : 'Fixar',
            child: FormaIconButton(
              icon: Icon(
                note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              color: note.pinned ? c.primaryColor : null,
              onPressed: cubit.togglePin,
            ),
          ),
          _ActionsMenu(state: state),
        ],
      ),
    );
  }

  Future<void> _editTitle(
    BuildContext context,
    NoteDetailCubit cubit,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renomear nota'),
        content: FormaTextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          FormaButton.secondary(
            label: 'Cancelar',
            small: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          FormaButton.primary(
            label: 'Salvar',
            small: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    if (result != null) await cubit.updateTitle(result);
  }
}

class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({required this.state});

  final NoteDetailState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NoteDetailCubit>();
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (value) => _onSelected(context, cubit, value),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'copy', child: Text('Copiar transcrição')),
        PopupMenuItem(value: 'md', child: Text('Exportar .md')),
        PopupMenuItem(value: 'txt', child: Text('Exportar .txt')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Apagar nota')),
      ],
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    NoteDetailCubit cubit,
    String value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (value) {
      case 'copy':
        await Clipboard.setData(
          ClipboardData(text: transcriptPlainText(state.segments)),
        );
        messenger.showSnackBar(
          const SnackBar(content: Text('Transcrição copiada.')),
        );
      case 'md':
        await _export(
          context,
          'md',
          noteMarkdown(state.note!, state.segments, state.tags),
        );
      case 'txt':
        await _export(context, 'txt', noteTxt(state.note!, state.segments));
      case 'delete':
        final confirmed = await _confirmDelete(context);
        if (confirmed) await cubit.delete();
    }
  }

  Future<void> _export(
    BuildContext context,
    String ext,
    String contents,
  ) async {
    final title = state.note!.title.trim();
    final name = (title.isEmpty ? 'nota' : title).replaceAll(
      RegExp(r'[^\w\s-]'),
      '',
    );
    final location = await getSaveLocation(suggestedName: '$name.$ext');
    if (location == null) return;
    await File(location.path).writeAsString(contents);
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar nota?'),
        content: const Text(
          'A nota, a transcrição e os áudios serão removidos. '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          FormaButton.secondary(
            label: 'Cancelar',
            small: true,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FormaButton.danger(
            label: 'Apagar',
            small: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({required this.state});

  final NoteDetailState state;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final cubit = context.read<NoteDetailCubit>();
    final total = state.audioDuration ?? Duration.zero;
    final position = state.position > total ? total : state.position;
    final hasAudio = state.note!.playbackPath != null && total > Duration.zero;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FormaSpacing.base,
        vertical: FormaSpacing.sm,
      ),
      child: Row(
        children: [
          FormaIconButton(
            icon: Icon(
              state.playing
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_fill,
            ),
            size: 36,
            color: c.primaryColor,
            onPressed: hasAudio ? cubit.togglePlay : null,
          ),
          const SizedBox(width: FormaSpacing.sm),
          Text(
            Formatters.duration(position),
            style: context.formaTypography.caption12.copyWith(
              color: c.textMuted,
            ),
          ),
          Expanded(
            child: Slider(
              value: total.inMilliseconds == 0
                  ? 0
                  : position.inMilliseconds
                        .clamp(0, total.inMilliseconds)
                        .toDouble(),
              max: total.inMilliseconds == 0
                  ? 1
                  : total.inMilliseconds.toDouble(),
              onChanged: hasAudio
                  ? (v) => cubit.seek(Duration(milliseconds: v.round()))
                  : null,
            ),
          ),
          Text(
            Formatters.duration(total),
            style: context.formaTypography.caption12.copyWith(
              color: c.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({required this.state});

  final NoteDetailState state;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    if (state.note!.status == NoteStatus.transcribing) {
      return const Center(
        child: FormaEmptyState(
          icon: Icons.graphic_eq_rounded,
          title: 'Transcrevendo…',
          message: 'A transcrição aparece aqui quando terminar.',
          compact: true,
        ),
      );
    }
    if (state.segments.isEmpty) {
      final failed = state.note!.status == NoteStatus.failed;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FormaEmptyState(
              icon: failed
                  ? Icons.error_outline_rounded
                  : Icons.subtitles_off_outlined,
              title: failed ? 'Falha na transcrição' : 'Sem transcrição',
              compact: true,
            ),
            if (failed) ...[
              const SizedBox(height: FormaSpacing.sm),
              FormaButton.secondary(
                label: 'Tentar de novo',
                small: true,
                onPressed: context.read<NoteDetailCubit>().retryTranscription,
              ),
            ],
          ],
        ),
      );
    }
    final active = state.activeSegmentIndex;
    final cubit = context.read<NoteDetailCubit>();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: FormaSpacing.base),
      itemCount: state.segments.length,
      itemBuilder: (context, i) {
        final segment = state.segments[i];
        final isActive = i == active;
        final isMe = segment.speaker == SegmentSpeaker.me;
        return InkWell(
          onTap: () => cubit.seekToSegment(segment),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.all(FormaSpacing.sm),
            decoration: BoxDecoration(
              color: isActive ? c.primarySurface : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isMe ? 'Eu' : 'Outros',
                      style: context.formaTypography.caption12Med.copyWith(
                        color: isMe ? c.primaryColor : c.accentColor,
                      ),
                    ),
                    const SizedBox(width: FormaSpacing.sm),
                    Text(
                      formatTimestamp(segment.startMs),
                      style: context.formaTypography.overline10.copyWith(
                        color: c.textHint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  segment.content,
                  style: context.formaTypography.body14.copyWith(
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TagsBar extends StatelessWidget {
  const _TagsBar({required this.state});

  final NoteDetailState state;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final cubit = context.read<NoteDetailCubit>();
    return Container(
      padding: const EdgeInsets.all(FormaSpacing.base),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Wrap(
        spacing: FormaSpacing.xs,
        runSpacing: FormaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in state.tags)
            InkWell(
              onTap: () => cubit.removeTag(tag.id),
              borderRadius: BorderRadius.circular(FormaRadius.chip),
              child: FormaChip(
                label: tag.displayLabel,
                icon: Icons.close_rounded,
                color: c.primaryColor,
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Tag'),
            onPressed: () => _addTag(context, cubit),
          ),
        ],
      ),
    );
  }

  Future<void> _addTag(BuildContext context, NoteDetailCubit cubit) async {
    final attached = state.tags.map((t) => t.id).toSet();
    final available = state.allTags
        .where((t) => !attached.contains(t.id))
        .toList();
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar tag'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (available.isNotEmpty)
              Wrap(
                spacing: FormaSpacing.xs,
                runSpacing: FormaSpacing.xs,
                children: [
                  for (final tag in available)
                    InkWell(
                      onTap: () {
                        unawaited(cubit.addTag(tag.id));
                        Navigator.of(dialogContext).pop();
                      },
                      child: FormaChip(
                        label: tag.displayLabel,
                      ),
                    ),
                ],
              ),
            const SizedBox(height: FormaSpacing.md),
            FormaTextField(
              controller: controller,
              hint: 'Nova tag',
              autofocus: true,
              onSubmitted: (v) {
                unawaited(cubit.createTagAndAttach(v));
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        ),
        actions: [
          FormaButton.secondary(
            label: 'Fechar',
            small: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }
}
