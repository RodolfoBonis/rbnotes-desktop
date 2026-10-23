import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/motion.dart';
import 'package:rbnotes/core/ui/pulse_dot.dart';
import 'package:rbnotes/core/ui/wave_bars.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';

/// HUD flutuante de gravação e de processamento (fundo escuro, base da janela).
/// Início do painel de detalhe (largura da sidebar + da lista de notas).
const double _detailPaneLeft = 228 + 304;

class RecordingHud extends StatelessWidget {
  const RecordingHud({super.key});

  static const _steps = [
    ('Transcrevendo com Whisper', 'no seu Mac'),
    ('Separando falantes e pontuação', 'no seu Mac'),
    ('Gerando título, resumo e insights', 'Claude'),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RecordingCubit, RecordingState>(
      builder: (context, state) {
        return AnimatedSwitcher(
          duration: reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: fadeScaleTransition,
          child: !state.isActive
              ? const SizedBox.shrink()
              : Padding(
                  // Centraliza o HUD sobre o painel de detalhe (à direita da
                  // sidebar + lista), não sobre a janela inteira.
                  key: ValueKey(state.isProcessing),
                  padding: const EdgeInsets.only(left: _detailPaneLeft),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: state.isProcessing
                          ? _ProcessingCard(state: state)
                          : _RecordingCard(state: state),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.state});
  final RecordingState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RecordingCubit>();
    final paused = state.status == RecordingStatus.paused;
    final shown = state.liveText.trim().split(' ');
    final head = shown.length > 3
        ? shown.sublist(0, shown.length - 3).join(' ')
        : '';
    final tail = shown.length > 3
        ? shown.sublist(shown.length - 3).join(' ')
        : state.liveText;
    return _DarkCard(
      width: 540,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (paused)
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: RbTokens.pausedDot,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const PulseDot(color: RbTokens.recDot, size: 9),
              const SizedBox(width: 10),
              Text(
                paused ? 'Pausado' : 'Gravando',
                style: context.bodyText(
                  size: 12,
                  weight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              const Spacer(),
              Text(
                Formatters.duration(state.elapsed),
                style: context.bodyText(
                  size: 20,
                  weight: FontWeight.w500,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 40,
            child: LiveWaveBars(
              count: 64,
              maxHeight: 40,
              active: !paused,
              colorFor: (i, n) => Colors.white.withValues(
                alpha: paused ? 0.25 : 0.25 + 0.75 * i / (n - 1),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 66,
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black],
                stops: [0, 0.4],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: head.isEmpty ? '' : '$head '),
                      TextSpan(
                        text: tail,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                  maxLines: 3,
                  style: context.bodyText(
                    size: 14,
                    height: 1.55,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transcrevendo ao vivo no seu Mac',
                  style: context.bodyText(
                    size: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
              _HudButton(
                label: 'Descartar',
                onTap: cubit.discard,
                color: Colors.white.withValues(alpha: 0.75),
              ),
              const SizedBox(width: 8),
              _HudButton(
                label: paused ? 'Continuar' : 'Pausar',
                onTap: paused ? cubit.resume : cubit.pause,
                background: Colors.white.withValues(alpha: 0.12),
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              _HudButton(
                label: 'Concluir',
                onTap: cubit.stop,
                background: Colors.white,
                color: const Color(0xFF1D1D1F),
                leadingSquare: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard({required this.state});
  final RecordingState state;

  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Preparando sua nota · ${Formatters.duration(state.elapsed)}',
            style: context.bodyText(
              size: 12,
              weight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < RecordingHud._steps.length; i++)
            _StepRow(
              label: RecordingHud._steps[i].$1,
              where: RecordingHud._steps[i].$2,
              done: i < state.step,
              active: i == state.step,
              progress: state.stepProgress,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.where,
    required this.done,
    required this.active,
    required this.progress,
  });

  final String label;
  final String where;
  final bool done;
  final bool active;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final accent = context.rb.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: done ? accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: done
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(
                            alpha: active ? 0.8 : 0.25,
                          ),
                          width: 1.5,
                        ),
                ),
                child: done
                    ? const Icon(Icons.check, size: 9, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: context.bodyText(
                    size: 13,
                    color: done || active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
              Text(
                where,
                style: context.bodyText(
                  size: 11,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: const Color(0xF01C1C1E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.label,
    required this.onTap,
    required this.color,
    this.background,
    this.leadingSquare = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color? background;
  final bool leadingSquare;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: leadingSquare ? 11 : 13),
        decoration: BoxDecoration(
          color: background ?? Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadingSquare) ...[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: context.rb.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: context.bodyText(
                size: 12.5,
                weight: leadingSquare ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
