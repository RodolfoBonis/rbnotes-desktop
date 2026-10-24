import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/notes/data/note_repository.dart';
import 'package:rbnotes/features/sync/data/audio_upload_queue.dart';

/// Diálogo que mostra a fila de upload de áudio com o progresso por nota e um
/// botão "Tentar de novo" quando algum item falhou.
class AudioQueueDialog extends StatelessWidget {
  const AudioQueueDialog({
    required this.queue,
    required this.notes,
    super.key,
  });

  final AudioUploadQueue queue;
  final NoteRepository notes;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Dialog(
      backgroundColor: rb.bg3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Fila de upload de áudio', style: context.serif(size: 18)),
              const SizedBox(height: 14),
              Flexible(
                child: StreamBuilder<List<AudioUploadItem>>(
                  stream: queue.items,
                  initialData: queue.current,
                  builder: (context, snap) {
                    final items = snap.data ?? const [];
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Nenhum áudio na fila.',
                          style: context.bodyText(
                            size: 13,
                            color: rb.secondary(0.6),
                          ),
                        ),
                      );
                    }
                    final hasFailed = items.any(
                      (i) => i.status == AudioUploadStatus.failed,
                    );
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) =>
                                _ItemRow(item: items[i], notes: notes),
                          ),
                        ),
                        if (hasFailed) ...[
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerRight,
                            child: GestureDetector(
                              onTap: queue.retry,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                height: 30,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: rb.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Tentar de novo',
                                  style: context.bodyText(
                                    size: 12.5,
                                    weight: FontWeight.w600,
                                    color: rb.onAccent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.notes});

  final AudioUploadItem item;
  final NoteRepository notes;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder(
                future: notes.getNote(item.noteId),
                builder: (context, snap) {
                  final title = (snap.data?.title ?? '').trim();
                  return Text(
                    title.isEmpty ? 'Nota sem título' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.bodyText(size: 13, weight: FontWeight.w500),
                  );
                },
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: item.status == AudioUploadStatus.uploading
                      ? item.progress
                      : (item.status == AudioUploadStatus.failed ? 0 : null),
                  minHeight: 4,
                  backgroundColor: rb.controlFill,
                  valueColor: AlwaysStoppedAnimation(
                    item.status == AudioUploadStatus.failed
                        ? RbTokens.destructive
                        : rb.accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _statusLabel(item),
          style: context.bodyText(
            size: 11,
            color: item.status == AudioUploadStatus.failed
                ? RbTokens.destructive
                : rb.secondary(0.6),
          ),
        ),
      ],
    );
  }

  String _statusLabel(AudioUploadItem item) => switch (item.status) {
    AudioUploadStatus.uploading => '${(item.progress * 100).round()}%',
    AudioUploadStatus.failed => 'Falhou',
    AudioUploadStatus.pending => 'Na fila',
  };
}
