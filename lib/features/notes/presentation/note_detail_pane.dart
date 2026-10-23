import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/pulse_dot.dart';
import 'package:rbnotes/data/database/database.dart';
import 'package:rbnotes/features/notes/domain/note_models.dart';
import 'package:rbnotes/features/notes/presentation/note_view_cubit.dart';
import 'package:rbnotes/features/notes/presentation/widgets/waveform_player.dart';

/// Limite de confiança abaixo do qual a palavra é sublinhada (baixa confiança).
const _lowConfidence = 0.55;

/// Detalhe da nota: toolbar + metadados + player + abas.
class NoteDetailPane extends StatelessWidget {
  const NoteDetailPane({
    required this.onOpenAsk,
    required this.onStartRecording,
    required this.onExport,
    required this.onFixWord,
    super.key,
  });

  final VoidCallback onOpenAsk;
  final VoidCallback onStartRecording;
  final VoidCallback onExport;
  final ValueChanged<String> onFixWord;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return ColoredBox(
      color: rb.bg,
      child: Column(
        children: [
          _Toolbar(
            onOpenAsk: onOpenAsk,
            onStartRecording: onStartRecording,
            onExport: onExport,
          ),
          Expanded(
            child: BlocBuilder<NoteViewCubit, NoteViewState>(
              builder: (context, state) {
                if (state.note == null) {
                  return const SizedBox.shrink();
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onOpenAsk,
    required this.onStartRecording,
    required this.onExport,
  });

  final VoidCallback onOpenAsk;
  final VoidCallback onStartRecording;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: rb.onSurface(0.07), width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onOpenAsk,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 28,
              padding: const EdgeInsets.fromLTRB(11, 0, 10, 0),
              decoration: BoxDecoration(
                color: rb.controlFill,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(
                children: [
                  Text(
                    'Perguntar às notas',
                    style: context.bodyText(
                      size: 12.5,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '⌘K',
                    style: context.bodyText(size: 11, color: rb.secondary(0.5)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onExport,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(
                Icons.ios_share,
                size: 15,
                color: rb.secondary(0.75),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onStartRecording,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 30,
              padding: const EdgeInsets.fromLTRB(10, 0, 13, 0),
              decoration: BoxDecoration(
                color: rb.accent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Gravar',
                    style: context.bodyText(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '⌘R',
                    style: context.bodyText(
                      size: 11,
                      color: Colors.white.withValues(alpha: 0.75),
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
          style: context.serif(size: 30, height: 1.15, letterSpacing: -0.5),
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
              Text(
                'Renomear',
                style: context.bodyText(size: 11.5, color: rb.secondary(0.65)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        WaveformPlayer(
          peaks: state.peaks,
          positionMs: state.positionMs,
          durationMs: state.durationMs,
          playing: state.playing,
          speed: state.speed,
          onToggle: cubit.togglePlay,
          onSeekFraction: (f) => cubit.seekTo((f * state.durationMs).round()),
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
    return switch (state.tab) {
      NoteTab.resumo => _ResumoTab(state: state),
      NoteTab.trans => _TranscriptTab(
        state: state,
        speakers: speakers,
        onFixWord: onFixWord,
      ),
      NoteTab.ins => _InsightsTab(state: state),
      NoteTab.chat => _ChatTab(state: state),
    };
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ai?.tldr ?? 'Resumo em preparação…',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                              text: 'ouvir em '
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
    for (var i = 0; i < state.segments.length; i++) {
      if (state.segments[i].speaker == SegmentSpeaker.me) {
        map[i] = 'Você';
      } else {
        final named = segs.where((s) => s.index == i);
        map[i] = named.isNotEmpty ? named.first.speaker : 'Outros';
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
        margin: const EdgeInsets.symmetric(horizontal: -12),
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
                      Text(
                        speakerName,
                        style: context.bodyText(
                          size: 12,
                          weight: FontWeight.w600,
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

/// Texto do segmento como um Wrap de palavras; as de baixa confiança ficam
/// sublinhadas e abrem "Corrigir palavra" ao toque.
class _SegmentText extends StatelessWidget {
  const _SegmentText({
    required this.segment,
    required this.dimmed,
    required this.onFixWord,
  });

  final SegmentRow segment;
  final bool dimmed;
  final ValueChanged<String> onFixWord;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final baseStyle = context.bodyText(
      size: 14,
      height: 1.55,
      color: dimmed ? rb.secondary(0.6) : rb.text,
    );
    final words = TranscriptWord.decode(segment.wordsJson);
    if (words.isEmpty) {
      return Text(segment.content, style: baseStyle);
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final w in words)
          if (w.probability < _lowConfidence)
            GestureDetector(
              onTap: () => onFixWord(_clean(w.text)),
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
    return raw.replaceAll(
      RegExp(r'[\[\] ]'),
      '',
    ).split(',').where((s) => s.isNotEmpty).map(int.parse).toList();
  }
}
