import 'package:flutter/material.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

/// Player com waveform clicável, tempo, velocidade e botão play/pause.
class WaveformPlayer extends StatelessWidget {
  const WaveformPlayer({
    required this.peaks,
    required this.positionMs,
    required this.durationMs,
    required this.playing,
    required this.speed,
    required this.onToggle,
    required this.onSeekFraction,
    required this.onCycleSpeed,
    super.key,
  });

  final List<double> peaks;
  final int positionMs;
  final int durationMs;
  final bool playing;
  final double speed;
  final VoidCallback onToggle;
  final ValueChanged<double> onSeekFraction;
  final VoidCallback onCycleSpeed;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final frac = durationMs == 0 ? 0.0 : positionMs / durationMs;
    final bars = peaks.isEmpty ? List<double>.filled(84, 0.2) : peaks;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rb.onSurface(0.06), width: 0.5),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: rb.ink, shape: BoxShape.circle),
              child: Icon(
                playing ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 36,
            child: Text(
              Formatters.durationMs(positionMs),
              textAlign: TextAlign.right,
              style: context.bodyText(size: 11.5, color: rb.secondary(0.75)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => onSeekFraction(
                  (d.localPosition.dx / c.maxWidth).clamp(0, 1),
                ),
                child: SizedBox(
                  height: 34,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < bars.length; i++)
                        Container(
                          width: 2,
                          height: (4 + bars[i] * 26).clamp(4, 30),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(1),
                            color: (i + 0.5) / bars.length <= frac
                                ? rb.accent
                                : rb.secondary(0.24),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 36,
            child: Text(
              Formatters.durationMs(durationMs),
              style: context.bodyText(size: 11.5, color: rb.secondary(0.75)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onCycleSpeed,
            child: Container(
              height: 22,
              constraints: const BoxConstraints(minWidth: 34),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: rb.onSurface(0.12)),
              ),
              child: Text(
                '${_speedLabel(speed)}×',
                style: context.bodyText(
                  size: 11,
                  weight: FontWeight.w600,
                  color: rb.secondary(0.8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _speedLabel(double s) =>
      s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
}
