import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Renders a row of vertical bars (a waveform), spaced evenly. [heights] are
/// 0..1; [maxHeight] is the tallest bar in px. [colorFor] colors each bar.
class WaveBars extends StatelessWidget {
  const WaveBars({
    required this.heights,
    required this.maxHeight,
    required this.colorFor,
    this.barWidth = 3,
    this.minHeight = 3,
    super.key,
  });

  final List<double> heights;
  final double maxHeight;
  final double minHeight;
  final double barWidth;
  final Color Function(int index, int count) colorFor;

  @override
  Widget build(BuildContext context) {
    final n = heights.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < n; i++)
          Container(
            width: barWidth,
            height: (minHeight + heights[i] * (maxHeight - minHeight)).clamp(
              minHeight,
              maxHeight,
            ),
            decoration: BoxDecoration(
              color: colorFor(i, n),
              borderRadius: BorderRadius.circular(barWidth / 2),
            ),
          ),
      ],
    );
  }
}

/// A self-animating live waveform (login card, recording HUD). Scrolls a buffer
/// of pseudo-random heights left over time. Respects reduce-motion / [animate].
class LiveWaveBars extends StatefulWidget {
  const LiveWaveBars({
    required this.count,
    required this.maxHeight,
    required this.colorFor,
    this.animate = true,
    this.active = true,
    this.barWidth = 3,
    this.seed = 7,
    super.key,
  });

  final int count;
  final double maxHeight;
  final bool animate;

  /// When false the bars flatten (paused recording).
  final bool active;
  final double barWidth;
  final int seed;
  final Color Function(int index, int count) colorFor;

  @override
  State<LiveWaveBars> createState() => _LiveWaveBarsState();
}

class _LiveWaveBarsState extends State<LiveWaveBars>
    with SingleTickerProviderStateMixin {
  late List<double> _heights;
  Ticker? _ticker;
  int _t = 0;
  final _rnd = math.Random(42);

  @override
  void initState() {
    super.initState();
    _heights = _seeded();
  }

  List<double> _seeded() => List<double>.generate(widget.count, (i) {
    final env = 0.35 + 0.65 * math.sin((i + widget.seed) / 6).abs();
    return (0.15 + 0.5 * env).clamp(0.0, 1.0);
  });

  void _maybeStart() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.animate && !reduce) {
      _ticker ??= createTicker(_onTick)..start();
    }
  }

  void _onTick(Duration elapsed) {
    final step = elapsed.inMilliseconds ~/ 90;
    if (step == _t) return;
    _t = step;
    setState(() {
      final amp =
          0.35 + 0.65 * math.sin(_t / 5).abs() * math.sin(_t / 13 + 1).abs();
      final next = widget.active
          ? (0.08 + _rnd.nextDouble() * amp).clamp(0.0, 1.0)
          : 0.06;
      _heights = [..._heights.skip(1), next];
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStart();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WaveBars(
      heights: _heights,
      maxHeight: widget.maxHeight,
      barWidth: widget.barWidth,
      colorFor: widget.colorFor,
    );
  }
}
