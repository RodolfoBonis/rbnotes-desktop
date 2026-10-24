import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/security/presentation/app_lock_cubit.dart';

/// Cobre a janela inteira enquanto o app está travado: blur sobre o conteúdo
/// mais o botão "Desbloquear com Touch ID" (com fallback para a senha do Mac).
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final state = context.watch<AppLockCubit>().state;
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Material(
            type: MaterialType.transparency,
            child: ColoredBox(
              color: rb.bg.withValues(alpha: 0.72),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: rb.accentWash(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_outline,
                        size: 30,
                        color: rb.accent,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'RbNotes bloqueado',
                      style: context.serif(size: 24),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use o Touch ID para continuar',
                      style: context.bodyText(
                        size: 13,
                        color: rb.secondary(0.65),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _UnlockButton(authenticating: state.authenticating),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnlockButton extends StatelessWidget {
  const _UnlockButton({required this.authenticating});
  final bool authenticating;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: authenticating
          ? null
          : () => context.read<AppLockCubit>().unlock(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: rb.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: authenticating
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(rb.onAccent),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, size: 18, color: rb.onAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Desbloquear com Touch ID',
                    style: context.bodyText(
                      size: 13.5,
                      weight: FontWeight.w600,
                      color: rb.onAccent,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
