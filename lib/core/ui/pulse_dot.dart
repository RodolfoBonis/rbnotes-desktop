import 'package:flutter/material.dart';

/// A small circle that pulses its opacity (1 → 0.35 → 1), like the `rbpulse`
/// keyframes in the design (REC dot, "thinking" indicators). Honors
/// reduce-motion by staying fully opaque.
class PulseDot extends StatefulWidget {
  const PulseDot({
    required this.color,
    this.size = 8,
    this.period = const Duration(milliseconds: 1200),
    this.animate = true,
    super.key,
  });

  final Color color;
  final double size;
  final Duration period;
  final bool animate;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.animate && !reduce) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Opacity(
        opacity: 1 - 0.65 * _c.value,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
