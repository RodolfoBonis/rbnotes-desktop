import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:window_manager/window_manager.dart';

/// The macOS traffic-light buttons (close / minimize / zoom), drawn by the app
/// so they sit exactly where the design places them (top-left of the sidebar,
/// login and settings chrome). The window uses `TitleBarStyle.hidden` with the
/// native buttons hidden; these are wired to [windowManager].
///
/// [interactive] false renders decorative dots (used inside the settings modal,
/// where only the red one closes via [onClose]).
class TrafficLights extends StatelessWidget {
  const TrafficLights({super.key, this.onClose, this.interactive = true});

  /// Overrides the close action (e.g. closing a modal instead of the window).
  final VoidCallback? onClose;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(
          color: RbTokens.trafficRed,
          onTap: onClose ?? (interactive ? _close : null),
        ),
        const SizedBox(width: 8),
        _Dot(
          color: interactive
              ? RbTokens.trafficYellow
              : context.rb.onSurface(0.12),
          onTap: interactive ? _minimize : null,
        ),
        const SizedBox(width: 8),
        _Dot(
          color: interactive
              ? RbTokens.trafficGreen
              : context.rb.onSurface(0.12),
          onTap: interactive ? _zoom : null,
        ),
      ],
    );
  }

  static void _close() => _guard(windowManager.close());
  static void _minimize() => _guard(windowManager.minimize());
  static Future<void> _zoom() async {
    try {
      final maximized = await windowManager.isMaximized();
      await (maximized ? windowManager.unmaximize() : windowManager.maximize());
    } on Object catch (_) {
      // sem plugin (testes) — ignora.
    }
  }

  static void _guard(Future<void> future) {
    unawaited(future.catchError((Object _) {}));
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.onTap});

  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x26000000), width: 0.5),
        ),
      ),
    );
  }
}
