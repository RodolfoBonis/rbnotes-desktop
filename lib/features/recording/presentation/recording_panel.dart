import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:rbnotes/core/format/formatters.dart';
import 'package:rbnotes/features/recording/presentation/recording_cubit.dart';

/// Painel de gravação no topo da lista: gravar → pausar → parar, com medidor
/// por canal, cronômetro e o toggle de áudio do sistema.
class RecordingPanel extends StatelessWidget {
  const RecordingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return BlocBuilder<RecordingCubit, RecordingState>(
      builder: (context, state) {
        final cubit = context.read<RecordingCubit>();
        return Container(
          padding: const EdgeInsets.all(FormaSpacing.base),
          decoration: BoxDecoration(
            color: c.cardBackground,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _RecordButton(state: state, cubit: cubit),
                  const SizedBox(width: FormaSpacing.md),
                  Expanded(
                    child: state.isActive
                        ? Text(
                            Formatters.duration(state.elapsed),
                            style: context.formaTypography.h3,
                          )
                        : Text(
                            'Nova gravação',
                            style: context.formaTypography.body14.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                  ),
                  if (state.status == RecordingStatus.recording)
                    Tooltip(
                      message: 'Pausar',
                      child: FormaIconButton(
                        icon: const Icon(Icons.pause_rounded),
                        onPressed: cubit.pause,
                      ),
                    ),
                  if (state.status == RecordingStatus.paused)
                    Tooltip(
                      message: 'Retomar',
                      child: FormaIconButton(
                        icon: const Icon(Icons.play_arrow_rounded),
                        onPressed: cubit.resume,
                      ),
                    ),
                ],
              ),
              if (state.isActive) ...[
                const SizedBox(height: FormaSpacing.md),
                _LevelMeter(
                  label: 'Eu',
                  level: state.micLevel,
                  color: c.primaryColor,
                ),
                if (state.systemLevel != null) ...[
                  const SizedBox(height: FormaSpacing.xs),
                  _LevelMeter(
                    label: 'Sistema',
                    level: state.systemLevel!,
                    color: c.accentColor,
                  ),
                ],
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: FormaSpacing.sm),
                  child: Row(
                    children: [
                      FormaSwitch(
                        value: state.captureSystemAudio,
                        semanticLabel: 'Capturar áudio do sistema',
                        onChanged: (v) => cubit.setCaptureSystemAudio(value: v),
                      ),
                      const SizedBox(width: FormaSpacing.sm),
                      Expanded(
                        child: Text(
                          'Capturar áudio do sistema (reuniões)',
                          style: context.formaTypography.body13.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: FormaSpacing.sm),
                  child: Text(
                    state.error!,
                    style: context.formaTypography.caption12.copyWith(
                      color: c.errorColor,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.state, required this.cubit});

  final RecordingState state;
  final RecordingCubit cubit;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final active = state.isActive;
    return Semantics(
      button: true,
      label: active ? 'Parar gravação' : 'Iniciar gravação',
      child: InkWell(
        onTap: active ? cubit.stop : cubit.start,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? c.errorSurface : c.primaryColor,
            shape: BoxShape.circle,
          ),
          child: Icon(
            active ? Icons.stop_rounded : Icons.mic_rounded,
            color: active ? c.errorColor : c.resolvedOnPrimary,
          ),
        ),
      ),
    );
  }
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({
    required this.label,
    required this.level,
    required this.color,
  });

  final String label;
  final double level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(
            label,
            style: context.formaTypography.caption12.copyWith(
              color: c.textMuted,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: level.clamp(0, 1),
              minHeight: 6,
              backgroundColor: c.border,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
