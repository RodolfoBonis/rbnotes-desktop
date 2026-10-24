import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/rb_menu.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/ai/domain/note_ai.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/notes/domain/note_export.dart';

/// Ações do menu de contexto / "…" de uma nota (bug/pedido 9).
enum NoteAction {
  rename,
  move,
  favorite,
  duplicate,
  export,
  copyTranscript,
  retryTranscription,
  regenerateSummary,
  lock,
  unlock,
  delete,
}

/// Formatos de exportação.
enum NoteExportFormat { md, txt, zip }

/// Abre o menu de contexto da nota em [position] e executa a ação escolhida,
/// usando o [LibraryCubit] para as mutações. Reutilizado pelo clique direito na
/// lista e pelo menu "…" da toolbar do detalhe.
Future<void> showNoteContextMenu({
  required BuildContext context,
  required Offset position,
  required NoteRow note,
  required LibraryCubit library,
}) async {
  final action = await showRbMenu<NoteAction>(
    context: context,
    position: position,
    items: [
      const RbMenuItem(
        value: NoteAction.rename,
        label: 'Renomear',
        icon: Icons.edit_outlined,
      ),
      const RbMenuItem(
        value: NoteAction.move,
        label: 'Mover para pasta…',
        icon: Icons.folder_outlined,
        trailing: Icon(Icons.chevron_right, size: 16),
      ),
      RbMenuItem(
        value: NoteAction.favorite,
        label: note.favorite ? 'Desfavoritar' : 'Favoritar',
        icon: note.favorite ? Icons.star : Icons.star_border,
      ),
      const RbMenuItem(
        value: NoteAction.duplicate,
        label: 'Duplicar',
        icon: Icons.copy_outlined,
      ),
      const RbMenuItem(
        value: NoteAction.export,
        label: 'Exportar…',
        icon: Icons.ios_share,
        dividerAbove: true,
      ),
      const RbMenuItem(
        value: NoteAction.copyTranscript,
        label: 'Copiar transcrição',
        icon: Icons.content_copy_outlined,
      ),
      const RbMenuItem(
        value: NoteAction.retryTranscription,
        label: 'Tentar transcrever de novo',
        icon: Icons.graphic_eq,
        dividerAbove: true,
      ),
      const RbMenuItem(
        value: NoteAction.regenerateSummary,
        label: 'Gerar resumo de novo',
        icon: Icons.auto_awesome_outlined,
      ),
      if (note.locked)
        const RbMenuItem(
          value: NoteAction.unlock,
          label: 'Desbloquear',
          icon: Icons.lock_open_outlined,
          dividerAbove: true,
        )
      else
        const RbMenuItem(
          value: NoteAction.lock,
          label: 'Bloquear nota com Touch ID',
          icon: Icons.lock_outline,
          dividerAbove: true,
        ),
      const RbMenuItem(
        value: NoteAction.delete,
        label: 'Apagar',
        icon: Icons.delete_outline,
        destructive: true,
        dividerAbove: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  await runNoteAction(
    context: context,
    action: action,
    note: note,
    library: library,
    menuPosition: position,
  );
}

/// Executa [action] sobre [note]. Exposto para o menu "…" da toolbar reusar as
/// mesmas ações com um `anchor` próprio.
Future<void> runNoteAction({
  required BuildContext context,
  required NoteAction action,
  required NoteRow note,
  required LibraryCubit library,
  required Offset menuPosition,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  switch (action) {
    case NoteAction.rename:
      final name = await _promptRename(context, note.title);
      if (name != null) await library.renameNote(note.id, name);
    case NoteAction.move:
      if (!context.mounted) return;
      await _showMoveToFolder(context, note, library, menuPosition);
    case NoteAction.favorite:
      await library.toggleFavorite(note);
    case NoteAction.duplicate:
      await library.duplicateNote(note.id);
    case NoteAction.export:
      final bundle = await library.exportBundle(note.id);
      if (!context.mounted || bundle.note == null) return;
      await exportNoteData(
        context,
        note: bundle.note!,
        segments: bundle.segments,
        ai: bundle.ai,
      );
    case NoteAction.copyTranscript:
      final text = await library.transcriptText(note.id);
      await Clipboard.setData(ClipboardData(text: text));
      messenger?.showSnackBar(
        const SnackBar(content: Text('Transcrição copiada')),
      );
    case NoteAction.retryTranscription:
      await library.retryTranscription(note.id);
    case NoteAction.regenerateSummary:
      await library.regenerateSummary(note.id);
    case NoteAction.lock:
      await library.lockNote(note.id);
    case NoteAction.unlock:
      await library.unlockNote(note.id);
    case NoteAction.delete:
      final ok = await _confirmDelete(context, note.title);
      if (ok) await library.deleteNote(note.id);
  }
}

Future<void> _showMoveToFolder(
  BuildContext context,
  NoteRow note,
  LibraryCubit library,
  Offset position,
) async {
  final folders = library.state.folders.where((f) => !f.hidden).toList();
  final chosen = await showRbMenu<String>(
    context: context,
    position: position.translate(16, 16),
    width: 220,
    items: [
      const RbMenuItem(
        value: '',
        label: 'Sem pasta',
        icon: Icons.inbox_outlined,
      ),
      for (final f in folders)
        RbMenuItem(
          value: f.id,
          label: f.name,
          trailing: note.folderId == f.id
              ? const Icon(Icons.check, size: 15)
              : null,
        ),
    ],
  );
  if (chosen == null) return;
  await library.moveToFolder(note.id, chosen.isEmpty ? null : chosen);
}

Future<String?> _promptRename(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Renomear nota'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
        decoration: const InputDecoration(hintText: 'Título da nota'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
}

/// Confirma e apaga [note] (atalho ⌫/⌘⌫). Público para o app shell reusar.
Future<void> confirmAndDeleteNote(
  BuildContext context,
  NoteRow note,
  LibraryCubit library,
) async {
  if (await _confirmDelete(context, note.title)) {
    await library.deleteNote(note.id);
  }
}

Future<bool> _confirmDelete(BuildContext context, String title) async {
  final name = title.trim().isEmpty ? 'esta nota' : '“${title.trim()}”';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Apagar nota'),
      content: Text('Apagar $name? Esta ação pode ser sincronizada.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: RbTokens.destructive,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Apagar'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Pergunta o formato e grava o arquivo da nota (reutilizável por lista/detalhe).
Future<void> exportNoteData(
  BuildContext context, {
  required NoteRow note,
  required List<SegmentRow> segments,
  NoteAi? ai,
}) async {
  final format = await showDialog<NoteExportFormat>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Exportar nota'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(NoteExportFormat.md),
          child: const Text('Transcrição (.md)'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(NoteExportFormat.txt),
          child: const Text('Transcrição (.txt)'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(NoteExportFormat.zip),
          child: const Text('Pacote .zip (áudio + transcrição + resumo)'),
        ),
      ],
    ),
  );
  if (format == null) return;

  final base = _safeFileName(note.title.isEmpty ? 'nota' : note.title);
  switch (format) {
    case NoteExportFormat.md:
      await _saveBytes(
        '$base.md',
        utf8.encode(noteMarkdown(note, segments, const [])),
      );
    case NoteExportFormat.txt:
      await _saveBytes('$base.txt', utf8.encode(noteTxt(note, segments)));
    case NoteExportFormat.zip:
      final entries = <ZipEntry>[
        (
          name: 'transcricao.md',
          bytes: utf8.encode(noteMarkdown(note, segments, const [])),
        ),
        (name: 'resumo.md', bytes: utf8.encode(summaryMarkdown(note, ai))),
      ];
      final audioPath = note.playbackPath;
      if (audioPath != null && File(audioPath).existsSync()) {
        entries.add((
          name: '$base.m4a',
          bytes: File(audioPath).readAsBytesSync(),
        ));
      }
      await _saveBytes('$base.zip', buildZip(entries));
  }
}

Future<void> _saveBytes(String suggestedName, List<int> bytes) async {
  final location = await getSaveLocation(suggestedName: suggestedName);
  if (location == null) return;
  await File(location.path).writeAsBytes(bytes);
}

String _safeFileName(String title) {
  final cleaned = title.replaceAll(RegExp('[^a-zA-Z0-9À-ÿ _-]'), '').trim();
  return cleaned.isEmpty ? 'nota' : cleaned;
}
