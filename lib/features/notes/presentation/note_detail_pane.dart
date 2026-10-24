import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rbnotes/app/shell/detail_toolbar.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/motion.dart';
import 'package:rbnotes/core/ui/pulse_dot.dart';
import 'package:rbnotes/core/ui/rb_menu.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/library/presentation/library_cubit.dart';
import 'package:rbnotes/features/notes/domain/note_export.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/notes/domain/note_summary_status.dart';
import 'package:rbnotes/features/notes/presentation/note_actions.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/notes/presentation/widgets/waveform_player.dart';
import 'package:rbnotes/features/settings/data/settings_store.dart';

/// Limite de confiança abaixo do qual a palavra é sublinhada (baixa confiança).
const _lowConfidence = 0.55;

/// Detalhe da nota: toolbar + metadados + player + abas.
class NoteDetailPane extends StatelessWidget {
  const NoteDetailPane({
    required this.onOpenAsk,
    required this.onStartRecording,
    required this.onFixWord,
    super.key,
  });

  final VoidCallback onOpenAsk;
  final VoidCallback onStartRecording;
  final ValueChanged<String> onFixWord;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return ColoredBox(
      color: rb.bg,
      child: Column(
        children: [
          DetailToolbar(
            onOpenAsk: onOpenAsk,
            onStartRecording: onStartRecording,
            onExport: () => exportCurrentNote(context),
            onMore: (pos) {
              final note = context.read<NoteViewCubit>().state.note;
              if (note == null) return;
              unawaited(
                showNoteContextMenu(
                  context: context,
                  position: pos,
                  note: note,
                  library: context.read<LibraryCubit>(),
                ),
              );
            },
          ),
          Expanded(
            child: BlocBuilder<NoteViewCubit, NoteViewState>(
              builder: (context, state) {
                if (state.note == null) {
                  return const SizedBox.shrink();
                }
                if (state.needsUnlock) {
                  return const _LockedNotePlaceholder();
                }
                return SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(40, 34, 40, 140),
                        child: _NoteBody(state: state, onFixWord: onFixWord),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.state, required this.onFixWord});

  final NoteViewState state;
  final ValueChanged<String> onFixWord;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final note = state.note!;
    final cubit = context.read<NoteViewCubit>();
    final speakers = EnrichmentSpeakers.of(note.speakersJson);
    final folderColor = RbTokens.folderColor(note.folderId);
    final folderName = _folderName(note.folderId);
    final dateLong = _dateLong(note.createdAt);
    final speakersLabel = speakers.length > 1
        ? speakers.join(', ')
        : 'Nota pessoal';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: folderColor,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              folderName,
              style: context.bodyText(size: 12, color: rb.secondary(0.65)),
            ),
            _dotSep(context),
            Text(
              dateLong,
              style: context.bodyText(size: 12, color: rb.secondary(0.65)),
            ),
            _dotSep(context),
            Flexible(
              child: Text(
                speakersLabel,
                overflow: TextOverflow.ellipsis,
                style: context.bodyText(size: 12, color: rb.secondary(0.65)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          note.title,
          style: context.serif(
            size: 30,
            weight: FontWeight.w500,
            height: 1.15,
            letterSpacing: -0.5,
          ),
        ),
        if (note.autoTitle) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: rb.accentWash(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Título gerado pelo Claude',
                  style: context.bodyText(
                    size: 11.5,
                    weight: FontWeight.w600,
                    color: rb.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => renameCurrentNote(context, note),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'Renomear',
                  style: context.bodyText(
                    size: 11.5,
                    color: rb.secondary(0.65),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        WaveformPlayer(
          peaks: state.peaks,
          // Descontam os silêncios longos quando a nota tem silêncios salvos.
          positionMs: state.displayPositionMs,
          durationMs: state.displayDurationMs,
          playing: state.playing,
          speed: state.speed,
          onToggle: cubit.togglePlay,
          onSeekFraction: (f) =>
              cubit.seekToDisplay((f * state.displayDurationMs).round()),
          onCycleSpeed: cubit.cycleSpeed,
        ),
        const SizedBox(height: 26),
        _TabBar(state: state, onTap: cubit.setTab),
        const SizedBox(height: 22),
        _TabBody(state: state, speakers: speakers, onFixWord: onFixWord),
      ],
    );
  }

  Widget _dotSep(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      '·',
      style: context.bodyText(size: 12, color: context.rb.secondary(0.65)),
    ),
  );

  String _folderName(String? id) => switch (id) {
    'trabalho' => 'Trabalho',
    'pessoal' => 'Pessoal',
    'estudos' => 'Estudos',
    'ideias' => 'Ideias',
    'diario' => 'Diário',
    _ => 'Notas',
  };

  String _dateLong(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    final time = DateFormat('HH:mm', 'pt_BR').format(d);
    if (diff == 0) return 'Hoje, $time';
    if (diff == 1) return 'Ontem, $time';
    return '${DateFormat("d 'de' MMMM", 'pt_BR').format(d)}, $time';
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.state, required this.onTap});
  final NoteViewState state;
  final ValueChanged<NoteTab> onTap;

  static const List<(NoteTab, String)> _tabs = [
    (NoteTab.resumo, 'Resumo'),
    (NoteTab.trans, 'Transcrição'),
    (NoteTab.ins, 'Insights'),
    (NoteTab.chat, 'Conversa'),
  ];

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final hint = switch (state.tab) {
      NoteTab.trans => 'Whisper · transcrito no seu Mac',
      NoteTab.chat => 'Respostas baseadas só nesta nota',
      _ => 'Gerado por Claude a partir da transcrição',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: rb.controlFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              for (final (tab, label) in _tabs)
                GestureDetector(
                  onTap: () => onTap(tab),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: state.tab == tab ? rb.seg : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: state.tab == tab
                          ? [
                              BoxShadow(
                                color: rb.onSurface(0.12),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      style: context.bodyText(
                        size: 12.5,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Flexible(
          child: Text(
            hint,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: context.bodyText(size: 11, color: rb.secondary(0.55)),
          ),
        ),
      ],
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.state,
    required this.speakers,
    required this.onFixWord,
  });

  final NoteViewState state;
  final List<String> speakers;
  final ValueChanged<String> onFixWord;

  @override
  Widget build(BuildContext context) {
    final body = switch (state.tab) {
      NoteTab.resumo => _ResumoTab(state: state),
      NoteTab.trans => _TranscriptTab(
        state: state,
        speakers: speakers,
        onFixWord: onFixWord,
      ),
      NoteTab.ins => _InsightsTab(state: state),
      NoteTab.chat => _ChatTab(state: state),
    };
    return AnimatedSwitcher(
      duration: reduceMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: KeyedSubtree(key: ValueKey(state.tab), child: body),
    );
  }
}

// ---------------- Resumo ----------------

class _ResumoTab extends StatelessWidget {
  const _ResumoTab({required this.state});
  final NoteViewState state;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final ai = state.ai;
    final cubit = context.read<NoteViewCubit>();
    final skipPersonal =
        di.isRegistered<SettingsStore>() && di<SettingsStore>().skipPersonal;
    final status = state.summaryStatus(skipPersonal: skipPersonal);
    // Estados honestos (bug 6): só mostramos o resumo quando ele existe de
    // verdade; caso contrário, um card com o estado real e a ação certa.
    if (!status.showsSummary) {
      return _SummaryStatusCard(status: status);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ai?.tldr ?? '',
          style: context.serif(
            size: 18,
            weight: FontWeight.w400,
            height: 1.55,
          ),
        ),
        const SizedBox(height: 22),
        const _SectionCaps('Pontos principais'),
        const SizedBox(height: 10),
        for (final p in ai?.points ?? const <String>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: rb.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p,
                    style: context.bodyText(size: 14, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        if (ai?.quote != null) ...[
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final quote = ai!.quote!;
              return GestureDetector(
                onTap: () => cubit.jumpToTime(quote.atMs),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: rb.fill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '“${quote.text}”',
                        style: context.serif(
                          size: 15,
                          weight: FontWeight.w400,
                          height: 1.5,
                          style: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${quote.speaker} · '),
                            TextSpan(
                              text:
                                  'ouvir em '
                                  '${Formatters.durationMs(quote.atMs)}',
                              style: TextStyle(color: rb.accent),
                            ),
                          ],
                        ),
                        style: context.bodyText(
                          size: 11.5,
                          color: rb.secondary(0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// Card de estado honesto do Resumo (bug 6): transcrição falha, resumo
/// desativado (privacidade), em preparação (com status real do SSE) ou falha
/// do resumo — cada um com a ação certa.
class _SummaryStatusCard extends StatelessWidget {
  const _SummaryStatusCard({required this.status});

  final SummaryStatus status;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final cubit = context.read<NoteViewCubit>();

    final (icon, title, sub, actionLabel, onAction) = switch (status.kind) {
      SummaryStatusKind.transcriptionFailed => (
        Icons.error_outline,
        'Não foi possível transcrever',
        'A transcrição falhou. Você pode tentar de novo.',
        'Tentar de novo',
        cubit.retryTranscription,
      ),
      SummaryStatusKind.transcribing => (
        Icons.graphic_eq,
        'Transcrevendo a nota…',
        'O resumo começa assim que a transcrição terminar.',
        null,
        null,
      ),
      SummaryStatusKind.disabledPersonal => (
        Icons.lock_outline,
        'Resumo desativado para a pasta Pessoal',
        'Pela sua configuração de privacidade, estas notas ficam só com a '
            'transcrição local.',
        null,
        null,
      ),
      SummaryStatusKind.disabled => (
        Icons.auto_awesome_outlined,
        'Resumo desativado para esta nota',
        'Gere um resumo com a IA quando quiser.',
        'Gerar resumo',
        cubit.retrySummary,
      ),
      SummaryStatusKind.pending => (
        Icons.hourglass_empty,
        'Resumo em preparação…',
        status.detail ?? 'Na fila…',
        null,
        null,
      ),
      SummaryStatusKind.summaryFailed => (
        Icons.error_outline,
        'Não foi possível gerar o resumo',
        'A geração do resumo falhou. Tente novamente.',
        'Tentar de novo',
        cubit.retrySummary,
      ),
      SummaryStatusKind.ready => (
        Icons.check,
        '',
        '',
        null,
        null,
      ),
    };

    final isError =
        status.kind == SummaryStatusKind.transcriptionFailed ||
        status.kind == SummaryStatusKind.summaryFailed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isError ? RbTokens.destructive : rb.secondary(0.7),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: context.serif(size: 17, weight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              sub,
              style: context.bodyText(
                size: 13.5,
                height: 1.5,
                color: rb.secondary(0.7),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: _RetryButton(
                label: actionLabel,
                onTap: onAction,
                destructive: isError,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Botão pill "Tentar de novo"/"Gerar resumo" do card de estado.
class _RetryButton extends StatelessWidget {
  const _RetryButton({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: destructive
              ? RbTokens.destructive.withValues(alpha: 0.12)
              : rb.fill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: context.bodyText(
            size: 13,
            weight: FontWeight.w600,
            color: destructive ? RbTokens.destructive : rb.accent,
          ),
        ),
      ),
    );
  }
}

// ---------------- Transcrição ----------------

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab({
    required this.state,
    required this.speakers,
    required this.onFixWord,
  });

  final NoteViewState state;
  final List<String> speakers;
  final ValueChanged<String> onFixWord;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NoteViewCubit>();
    final names = _speakerNames(state);
    final colors = _speakerColors(context, names.values.toSet().toList());
    final tracking = state.playing || state.positionMs > 0;
    var active = -1;
    for (var i = 0; i < state.segments.length; i++) {
      if (state.segments[i].startMs <= state.positionMs) active = i;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < state.segments.length; i++)
          _SegmentRow(
            segment: state.segments[i],
            speakerName: names[i] ?? 'Outros',
            color: colors[names[i]] ?? context.rb.ink,
            isActive: tracking && i == active,
            dimmed: tracking && i != active,
            onSeek: () => cubit.seekTo(state.segments[i].startMs, play: true),
            onFixWord: onFixWord,
          ),
      ],
    );
  }

  Map<int, String> _speakerNames(NoteViewState state) {
    final map = <int, String>{};
    final segs = state.ai?.speakerNames.segments ?? const [];
    final diar = state.speakerLabels;
    for (var i = 0; i < state.segments.length; i++) {
      if (state.segments[i].speaker == SegmentSpeaker.me) {
        map[i] = 'Você';
      } else {
        // Preferência: nome inferido pelo Claude > rótulo da diarização
        // ("Pessoa N") > genérico "Outros".
        final named = segs.where((s) => s.index == i);
        map[i] = named.isNotEmpty ? named.first.speaker : (diar[i] ?? 'Outros');
      }
    }
    return map;
  }

  Map<String, Color> _speakerColors(BuildContext context, List<String> names) {
    final palette = context.rb.speakerColors;
    final ordered = ['Você', ...names.where((n) => n != 'Você')];
    final map = <String, Color>{};
    for (var i = 0; i < ordered.length; i++) {
      map[ordered[i]] = palette[i % palette.length];
    }
    return map;
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.speakerName,
    required this.color,
    required this.isActive,
    required this.dimmed,
    required this.onSeek,
    required this.onFixWord,
  });

  final SegmentRow segment;
  final String speakerName;
  final Color color;
  final bool isActive;
  final bool dimmed;
  final VoidCallback onSeek;
  final ValueChanged<String> onFixWord;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final initials = speakerName
        .replaceAll('Dra. ', '')
        .replaceAll('Prof. ', '')
        .characters
        .first;
    return GestureDetector(
      onTap: onSeek,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? rb.accentWash(0.09) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      GestureDetector(
                        onTap: () => _renameSpeaker(context, speakerName),
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          speakerName,
                          style: context.bodyText(
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Formatters.durationMs(segment.startMs),
                        style: context.bodyText(
                          size: 11,
                          color: rb.secondary(0.55),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  _SegmentText(
                    segment: segment,
                    dimmed: dimmed,
                    onFixWord: onFixWord,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo para renomear um falante em toda a nota.
Future<void> _renameSpeaker(BuildContext context, String current) async {
  final cubit = context.read<NoteViewCubit>();
  final controller = TextEditingController(text: current);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Renomear falante'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
        decoration: const InputDecoration(hintText: 'Nome do falante'),
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
  if (name != null && name.trim().isNotEmpty) {
    await cubit.renameSpeaker(current, name.trim());
  }
}

/// Texto do segmento: Wrap de palavras (baixa confiança sublinhada). Duplo
/// clique edita o texto inline (Enter salva, Esc cancela).
class _SegmentText extends StatefulWidget {
  const _SegmentText({
    required this.segment,
    required this.dimmed,
    required this.onFixWord,
  });

  final SegmentRow segment;
  final bool dimmed;
  final ValueChanged<String> onFixWord;

  @override
  State<_SegmentText> createState() => _SegmentTextState();
}

class _SegmentTextState extends State<_SegmentText> {
  bool _editing = false;
  late final TextEditingController _controller = TextEditingController(
    text: widget.segment.content,
  );
  final FocusNode _focusNode = FocusNode();

  void _startEdit() {
    _controller.text = widget.segment.content;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    setState(() => _editing = false);
    if (text.isNotEmpty && text != widget.segment.content) {
      await context.read<NoteViewCubit>().editSegment(
        widget.segment.id,
        text,
      );
    }
  }

  void _cancel() => setState(() => _editing = false);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !shift) {
      unawaited(_save());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final baseStyle = context.bodyText(
      size: 14,
      height: 1.55,
      color: widget.dimmed ? rb.secondary(0.6) : rb.text,
    );
    if (_editing) {
      return Focus(
        onKeyEvent: _onKey,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          maxLines: null,
          style: baseStyle,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            filled: true,
            fillColor: rb.fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: rb.accent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: rb.accent),
            ),
          ),
          onEditingComplete: _save,
        ),
      );
    }
    return GestureDetector(
      onDoubleTap: _startEdit,
      behavior: HitTestBehavior.opaque,
      child: _buildDisplay(context, baseStyle),
    );
  }

  Widget _buildDisplay(BuildContext context, TextStyle baseStyle) {
    final rb = context.rb;
    final words = TranscriptWord.decode(widget.segment.wordsJson);
    if (words.isEmpty) {
      return Text(widget.segment.content, style: baseStyle);
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final w in words)
          if (w.probability < _lowConfidence)
            GestureDetector(
              onTap: () => widget.onFixWord(_clean(w.text)),
              behavior: HitTestBehavior.opaque,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: rb.accentWash(0.12),
                  borderRadius: BorderRadius.circular(3),
                  border: Border(
                    bottom: BorderSide(color: rb.accent),
                  ),
                ),
                child: Text('${w.text} ', style: baseStyle),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(w.text, style: baseStyle),
            ),
      ],
    );
  }

  String _clean(String s) => s.replaceAll(RegExp(r'[.,;:!?]+$'), '');
}

// ---------------- Insights ----------------

class _InsightsTab extends StatelessWidget {
  const _InsightsTab({required this.state});
  final NoteViewState state;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final cubit = context.read<NoteViewCubit>();
    final ai = state.ai;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionCaps('Próximas ações'),
        const SizedBox(height: 6),
        for (final a in state.actions)
          GestureDetector(
            onTap: () => cubit.toggleAction(a),
            onSecondaryTapDown: (d) =>
                unawaited(_taskMenu(context, a, d.globalPosition)),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: rb.onSurface(0.07), width: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 1),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: a.done ? rb.accent : Colors.transparent,
                      shape: BoxShape.circle,
                      border: a.done
                          ? null
                          : Border.all(color: rb.secondary(0.3), width: 1.5),
                    ),
                    child: a.done
                        ? const Icon(Icons.check, size: 11, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.content,
                          style: context
                              .bodyText(
                                size: 14,
                                height: 1.45,
                                color: a.done ? rb.secondary(0.5) : rb.text,
                              )
                              .copyWith(
                                decoration: a.done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                        ),
                        if (a.owner != null)
                          Text(
                            a.owner!,
                            style: context.bodyText(
                              size: 11.5,
                              color: rb.secondary(0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 26),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _InsightCard(
                title: 'Decisões',
                items: ai?.decisions ?? const [],
                emptyText: 'Nenhuma decisão registrada.',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _InsightCard(
                title: 'Em aberto',
                items: ai?.questions ?? const [],
                emptyText: 'Nada em aberto.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _TaskMenu { edit, delete }

Future<void> _taskMenu(
  BuildContext context,
  ActionRow action,
  Offset position,
) async {
  final cubit = context.read<NoteViewCubit>();
  final choice = await showRbMenu<_TaskMenu>(
    context: context,
    position: position,
    width: 200,
    items: const [
      RbMenuItem(
        value: _TaskMenu.edit,
        label: 'Editar tarefa',
        icon: Icons.edit_outlined,
      ),
      RbMenuItem(
        value: _TaskMenu.delete,
        label: 'Apagar tarefa',
        icon: Icons.delete_outline,
        destructive: true,
      ),
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _TaskMenu.edit:
      await _editTaskDialog(context, action, cubit);
    case _TaskMenu.delete:
      await cubit.deleteAction(action.id);
  }
}

Future<void> _editTaskDialog(
  BuildContext context,
  ActionRow action,
  NoteViewCubit cubit,
) async {
  final contentCtrl = TextEditingController(text: action.content);
  final ownerCtrl = TextEditingController(text: action.owner ?? '');
  var due = action.due;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Editar tarefa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Tarefa'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ownerCtrl,
              decoration: const InputDecoration(labelText: 'Responsável'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    due == null
                        ? 'Sem prazo'
                        : 'Prazo: ${DateFormat('dd/MM/yyyy').format(due!)}',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: due ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => due = picked);
                  },
                  child: const Text('Escolher'),
                ),
                if (due != null)
                  TextButton(
                    onPressed: () => setState(() => due = null),
                    child: const Text('Limpar'),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final owner = ownerCtrl.text.trim();
  await cubit.editAction(
    action.id,
    content: contentCtrl.text.trim().isEmpty ? null : contentCtrl.text.trim(),
    owner: owner.isEmpty ? null : owner,
    clearOwner: owner.isEmpty,
    due: due,
    clearDue: due == null,
  );
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final List<String> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionCaps(title),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              emptyText,
              style: context.bodyText(size: 13, color: rb.secondary(0.55)),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  item,
                  style: context.bodyText(size: 13, height: 1.5),
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------- Conversa ----------------

class _ChatTab extends StatelessWidget {
  const _ChatTab({required this.state});
  final NoteViewState state;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final cubit = context.read<NoteViewCubit>();
    final hasMessages =
        state.chat.isNotEmpty ||
        state.chatThinking ||
        state.streamingText != null;
    final suggestions =
        EnrichmentSpeakers.of(state.note?.speakersJson).length > 1
        ? const [
            'O que eu prometi fazer?',
            'Houve algum desacordo?',
            'Escreva um e-mail de follow-up',
          ]
        : const [
            'Resuma em uma frase',
            'Transforme em lista de tarefas',
            'O que eu prometi fazer?',
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasMessages) ...[
          Text(
            'Pergunte qualquer coisa sobre esta nota.',
            style: context.serif(size: 18, weight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'As respostas usam só esta transcrição e apontam o trecho do '
            'áudio de onde vieram.',
            style: context.bodyText(
              size: 13,
              height: 1.5,
              color: rb.secondary(0.65),
            ),
          ),
          const SizedBox(height: 18),
        ],
        for (final m in state.chat)
          _ChatBubble(message: m, onCite: cubit.jumpToTime),
        if (state.streamingText != null)
          _AiMessage(
            text: state.streamingText!,
            cites: const [],
            onCite: cubit.jumpToTime,
          ),
        if (state.chatThinking)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                PulseDot(
                  color: rb.accent,
                  size: 7,
                  period: const Duration(seconds: 1),
                ),
                const SizedBox(width: 10),
                Text(
                  'Lendo a transcrição…',
                  style: context.bodyText(size: 13, color: rb.secondary(0.65)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in suggestions)
              GestureDetector(
                onTap: () => cubit.sendChat(s),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rb.controlFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(s, style: context.bodyText(size: 12.5)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _ChatInput(
          value: state.chatInput,
          onChanged: cubit.setChatInput,
          onSend: cubit.sendChat,
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.onCite});
  final ChatMessageRow message;
  final ValueChanged<int> onCite;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    if (message.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 18, left: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: rb.accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(17),
              topRight: Radius.circular(17),
              bottomLeft: Radius.circular(17),
              bottomRight: Radius.circular(5),
            ),
          ),
          child: Text(
            message.content,
            style: context.bodyText(
              size: 14,
              height: 1.45,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return _AiMessage(
      text: message.content,
      cites: NoteAiRepositoryCites.of(message.citesJson),
      onCite: onCite,
    );
  }
}

class _AiMessage extends StatelessWidget {
  const _AiMessage({
    required this.text,
    required this.cites,
    required this.onCite,
  });

  final String text;
  final List<int> cites;
  final ValueChanged<int> onCite;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      margin: const EdgeInsets.only(bottom: 18, right: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Claude',
            style: context.bodyText(
              size: 11,
              weight: FontWeight.w600,
              color: rb.secondary(0.55),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: context.bodyText(size: 14.5, height: 1.6),
          ),
          if (cites.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in cites)
                  GestureDetector(
                    onTap: () => onCite(c),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 24,
                      padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rb.accentWash(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '▶ ouvir ${Formatters.durationMs(c)}',
                        style: context.bodyText(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: rb.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.value,
    required this.onChanged,
    required this.onSend,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 16, right: 5),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(21),
        border: Border.all(color: rb.onSurface(0.08), width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: value)
                ..selection = TextSelection.collapsed(offset: value.length),
              onChanged: onChanged,
              onSubmitted: (_) => onSend(),
              cursorColor: rb.accent,
              style: context.bodyText(size: 14),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Pergunte sobre esta nota',
                hintStyle: context.bodyText(
                  size: 14,
                  color: rb.secondary(0.45),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: rb.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCaps extends StatelessWidget {
  const _SectionCaps(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: context.bodyText(
        size: 11,
        weight: FontWeight.w600,
        letterSpacing: 0.4,
        color: context.rb.secondary(0.55),
      ),
    );
  }
}

/// Decodifica citações de uma mensagem do chat.
abstract final class NoteAiRepositoryCites {
  static List<int> of(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .replaceAll(
          RegExp(r'[\[\] ]'),
          '',
        )
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();
  }
}

/// Formatos de exportação oferecidos pela nota.
enum _ExportFormat { markdown, txt, zip }

/// Mostra um diálogo de renomear o título da nota atual.
Future<void> renameCurrentNote(BuildContext context, NoteRow note) async {
  final cubit = context.read<NoteViewCubit>();
  final controller = TextEditingController(text: note.title);
  final newTitle = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Renomear nota'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Título da nota'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
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
  controller.dispose();
  if (newTitle != null && newTitle.trim().isNotEmpty) {
    await cubit.renameTitle(newTitle);
  }
}

/// Exporta a nota atual: escolhe o formato e grava o arquivo via file_selector.
Future<void> exportCurrentNote(BuildContext context) async {
  final cubit = context.read<NoteViewCubit>();
  final state = cubit.state;
  final note = state.note;
  if (note == null) return;

  final format = await showDialog<_ExportFormat>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Exportar nota'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(_ExportFormat.markdown),
          child: const Text('Transcrição (.md)'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(_ExportFormat.txt),
          child: const Text('Transcrição (.txt)'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(ctx).pop(_ExportFormat.zip),
          child: const Text('Pacote .zip (áudio + transcrição + resumo)'),
        ),
      ],
    ),
  );
  if (format == null) return;

  final base = _safeFileName(note.title.isEmpty ? 'nota' : note.title);
  switch (format) {
    case _ExportFormat.markdown:
      await _saveBytes(
        '$base.md',
        utf8.encode(noteMarkdown(note, state.segments, const [])),
      );
    case _ExportFormat.txt:
      await _saveBytes('$base.txt', utf8.encode(noteTxt(note, state.segments)));
    case _ExportFormat.zip:
      final entries = <ZipEntry>[
        (
          name: 'transcricao.md',
          bytes: utf8.encode(noteMarkdown(note, state.segments, const [])),
        ),
        (
          name: 'resumo.md',
          bytes: utf8.encode(summaryMarkdown(note, state.ai)),
        ),
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

/// Deixa o título seguro para nome de arquivo.
String _safeFileName(String title) {
  final cleaned = title.replaceAll(RegExp('[^a-zA-Z0-9À-ÿ _-]'), '').trim();
  return cleaned.isEmpty ? 'nota' : cleaned;
}

/// Mostrado no lugar do conteúdo quando a nota está bloqueada e a sessão de
/// desbloqueio ainda não foi aberta (pede Touch ID).
class _LockedNotePlaceholder extends StatelessWidget {
  const _LockedNotePlaceholder();

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: rb.accentWash(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_outline, size: 28, color: rb.accent),
          ),
          const SizedBox(height: 16),
          Text('Nota bloqueada', style: context.serif(size: 22)),
          const SizedBox(height: 6),
          Text(
            'Esta nota está protegida por Touch ID.',
            style: context.bodyText(size: 13, color: rb.secondary(0.65)),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => unawaited(context.read<NoteViewCubit>().unlockNote()),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rb.accent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, size: 17, color: rb.onAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Abrir com Touch ID',
                    style: context.bodyText(
                      size: 13,
                      weight: FontWeight.w600,
                      color: rb.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
