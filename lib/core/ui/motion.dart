import 'package:flutter/material.dart';

/// `true` quando o usuário pediu "Reduzir movimento" (Ajustes de Acessibilidade
/// do macOS) — todas as animações do app devem respeitar.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// Transição padrão de entrada de HUDs/overlays: fade + leve escala.
///
/// Usada como `transitionBuilder` de [AnimatedSwitcher] e por [FadeScaleIn].
Widget fadeScaleTransition(Widget child, Animation<double> animation) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.96, end: 1).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: child,
    ),
  );
}

/// Anima a entrada de [child] (fade + escala) quando ele é montado — para
/// overlays que aparecem/desaparecem por um booleano. Respeita "Reduzir
/// movimento": nesse caso aparece instantaneamente.
class FadeScaleIn extends StatelessWidget {
  const FadeScaleIn({
    required this.child,
    this.duration = const Duration(milliseconds: 180),
    super.key,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
      child: child,
    );
  }
}
