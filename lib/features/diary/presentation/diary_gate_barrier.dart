import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/features/diary/presentation/diary_gate.dart';

/// Cobre o conteúdo do Diário até o Touch ID abrir a sessão do [DiaryGate]
/// (M12). Ao entrar, pede a autenticação uma vez; se falhar, oferece repetir.
class DiaryGateBarrier extends StatefulWidget {
  const DiaryGateBarrier({required this.child, super.key});

  final Widget child;

  @override
  State<DiaryGateBarrier> createState() => _DiaryGateBarrierState();
}

class _DiaryGateBarrierState extends State<DiaryGateBarrier> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !context.read<DiaryGate>().state) {
        unawaited(context.read<DiaryGate>().ensure());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiaryGate, bool>(
      builder: (context, unlocked) =>
          unlocked ? widget.child : const _DiaryLocked(),
    );
  }
}

class _DiaryLocked extends StatelessWidget {
  const _DiaryLocked();

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: rb.accentWash(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lock_outline, size: 28, color: rb.accent),
          ),
          const SizedBox(height: 16),
          Text('Diário protegido', style: context.serif(size: 22)),
          const SizedBox(height: 6),
          Text(
            'Use o Touch ID para abrir seu diário.',
            style: context.bodyText(size: 13, color: rb.secondary(0.65)),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => unawaited(context.read<DiaryGate>().ensure()),
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rb.accent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, size: 17, color: rb.onAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Abrir o Diário com Touch ID',
                    style: context.bodyText(
                      size: 13,
                      weight: FontWeight.w600,
                      color: rb.onAccent,
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
