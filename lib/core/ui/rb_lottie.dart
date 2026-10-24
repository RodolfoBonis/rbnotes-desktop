import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Envolve `Lottie.asset` respeitando "Reduzir movimento" (mostra o primeiro
/// quadro parado) e caindo para [fallback] se o asset falhar ao carregar.
///
/// Quando [recolor] é informado, a animação é retinta para essa cor
/// (preservando o alfa de cada quadro), acompanhando o acento escolhido pelo
/// usuário. Usa um [ColorFilter] em vez de `ValueDelegate`/key-path porque o
/// key-path curinga quebra em alguns assets (resolveKeyPath).
class RbLottie extends StatelessWidget {
  const RbLottie({
    required this.asset,
    this.size = 72,
    this.fallback = const SizedBox.shrink(),
    this.recolor,
    super.key,
  });

  final String asset;
  final double size;
  final Widget fallback;
  final Color? recolor;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tint = recolor;
    final lottie = Lottie.asset(
      asset,
      width: size,
      height: size,
      repeat: !reduceMotion,
      animate: !reduceMotion,
      errorBuilder: (_, _, _) => fallback,
    );
    if (tint == null) return lottie;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(tint, BlendMode.srcATop),
      child: lottie,
    );
  }
}
