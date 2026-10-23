import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Envolve `Lottie.asset` respeitando "Reduzir movimento" (mostra o primeiro
/// quadro parado) e caindo para [fallback] se o asset falhar ao carregar.
class RbLottie extends StatelessWidget {
  const RbLottie({
    required this.asset,
    this.size = 72,
    this.fallback = const SizedBox.shrink(),
    super.key,
  });

  final String asset;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Lottie.asset(
      asset,
      width: size,
      height: size,
      repeat: !reduceMotion,
      animate: !reduceMotion,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
