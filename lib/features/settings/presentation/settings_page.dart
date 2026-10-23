import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forma_ui/forma_ui.dart';
import 'package:rbnotes/app/theme_mode_cubit.dart';
import 'package:rbnotes/core/di/injector.dart';
import 'package:rbnotes/features/settings/presentation/hotkey_editor.dart';
import 'package:rbnotes/features/settings/presentation/settings_cubit.dart';
import 'package:rbnotes/features/transcription/presentation/model_download_cubit.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Tela de configurações: aparência, gravação, transcrição, ditado e
/// permissões do sistema.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) {
            final cubit = SettingsCubit(
              store: di(),
              native: di(),
              dictation: di(),
            );
            unawaited(cubit.refreshPermissions());
            return cubit;
          },
        ),
        BlocProvider(
          create: (_) {
            final cubit = ModelDownloadCubit(native: di(), settings: di());
            unawaited(cubit.check());
            return cubit;
          },
        ),
      ],
      child: const _SettingsBody(),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        return ListView(
          padding: const EdgeInsets.all(FormaSpacing.xl),
          children: [
            Text('Configurações', style: context.formaTypography.h2),
            const SizedBox(height: FormaSpacing.lg),
            _Section(
              title: 'Aparência',
              children: [_ThemeRow()],
            ),
            _Section(
              title: 'Gravação',
              children: [
                _SwitchRow(
                  label: 'Capturar áudio do sistema por padrão',
                  description:
                      'Novas gravações já vêm com o áudio do sistema ligado.',
                  value: state.captureSystemAudio,
                  onChanged: (v) => cubit.setCaptureSystemAudio(value: v),
                ),
              ],
            ),
            const _Section(
              title: 'Transcrição',
              children: [_ModelRow()],
            ),
            _Section(
              title: 'Ditado global',
              children: [
                _SwitchRow(
                  label: 'Ativar ditado global',
                  description: 'Use o atalho para ditar em qualquer app.',
                  value: state.dictationEnabled,
                  onChanged: (v) => cubit.setDictationEnabled(value: v),
                ),
                _HotkeyRow(state: state),
                _DictationModeRow(state: state),
                if (state.dictationEnabled &&
                    state.hotkeyStatus.error != null)
                  _HotkeyErrorRow(message: state.hotkeyStatus.error!),
              ],
            ),
            _Section(
              title: 'Permissões',
              children: [
                for (final p in RbPermission.values)
                  _PermissionRow(permission: p, status: state.statusOf(p)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: FormaSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: FormaSpacing.sm),
            child: Text(
              title.toUpperCase(),
              style: context.formaTypography.overline10.copyWith(
                color: c.textHint,
              ),
            ),
          ),
          FormaCard(
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.trailing, this.description});

  final String label;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FormaSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.formaTypography.body14Medium),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: context.formaTypography.caption12.copyWith(
                      color: c.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: FormaSpacing.base),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Row(
      label: label,
      description: description,
      trailing: FormaSwitch(value: value, onChanged: onChanged),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeModeCubit>().state;
    return _Row(
      label: 'Tema',
      trailing: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
          ButtonSegment(value: ThemeMode.dark, label: Text('Escuro')),
          ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
        ],
        selected: {mode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => context.read<ThemeModeCubit>().set(s.first),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final settings = context.read<SettingsCubit>();
    return BlocBuilder<ModelDownloadCubit, ModelDownloadState>(
      builder: (context, state) {
        final download = context.read<ModelDownloadCubit>();
        return Column(
          children: [
            _Row(
              label: 'Modelo whisper',
              trailing: DropdownButton<WhisperModel>(
                value: settings.state.model,
                underline: const SizedBox.shrink(),
                items: [
                  for (final m in WhisperModel.values)
                    DropdownMenuItem(value: m, child: Text(m.label)),
                ],
                onChanged: (m) async {
                  if (m == null) return;
                  await settings.setModel(m);
                  await download.check();
                },
              ),
            ),
            const Divider(height: 1),
            _Row(
              label: 'Arquivo do modelo',
              description: switch (state.status) {
                ModelStatus.downloaded => 'Baixado e pronto.',
                ModelStatus.downloading =>
                  'Baixando… ${(state.progress * 100).round()}%',
                ModelStatus.failed => 'Falha ao baixar.',
                _ => 'Ainda não baixado.',
              },
              trailing: switch (state.status) {
                ModelStatus.downloaded => Icon(
                  Icons.check_circle_rounded,
                  color: c.successColor,
                ),
                ModelStatus.downloading => SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    value: state.progress == 0 ? null : state.progress,
                  ),
                ),
                _ => FormaButton.primary(
                  label: 'Baixar',
                  small: true,
                  onPressed: download.download,
                ),
              },
            ),
          ],
        );
      },
    );
  }
}

class _HotkeyRow extends StatelessWidget {
  const _HotkeyRow({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Row(
      label: 'Atalho do ditado',
      trailing: FormaButton.secondary(
        label: describeHotkey(state.hotkey),
        small: true,
        onPressed: () async {
          final result = await showHotkeyEditor(context, state.hotkey);
          if (result != null) await cubit.setHotkey(result);
        },
      ),
    );
  }
}

class _DictationModeRow extends StatelessWidget {
  const _DictationModeRow({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return _Row(
      label: 'Modo do ditado',
      trailing: SegmentedButton<DictationMode>(
        segments: const [
          ButtonSegment(
            value: DictationMode.holdToTalk,
            label: Text('Segurar'),
          ),
          ButtonSegment(value: DictationMode.toggle, label: Text('Alternar')),
        ],
        selected: {state.dictationMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => cubit.setDictationMode(s.first),
      ),
    );
  }
}

class _HotkeyErrorRow extends StatelessWidget {
  const _HotkeyErrorRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FormaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: c.errorColor),
          const SizedBox(width: FormaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Atalho não registrado',
                  style: context.formaTypography.body14Medium.copyWith(
                    color: c.errorColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Verifique a permissão de Acessibilidade abaixo. '
                  'Detalhe: $message',
                  style: context.formaTypography.caption12.copyWith(
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.permission, required this.status});

  final RbPermission permission;
  final PermissionStatus status;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<FormaThemeExtension>()!;
    final cubit = context.read<SettingsCubit>();
    final granted = status == PermissionStatus.granted;
    return _Row(
      label: _label(permission),
      description: _description(permission),
      trailing: granted
          ? Icon(Icons.check_circle_rounded, color: c.successColor)
          : FormaButton.secondary(
              label: permission == RbPermission.microphone
                  ? 'Permitir'
                  : 'Abrir Ajustes',
              small: true,
              onPressed: () => cubit.requestPermission(permission),
            ),
    );
  }

  String _label(RbPermission p) => switch (p) {
    RbPermission.microphone => 'Microfone',
    RbPermission.screenRecording => 'Gravação de tela',
    RbPermission.accessibility => 'Acessibilidade',
  };

  String _description(RbPermission p) => switch (p) {
    RbPermission.microphone => 'Necessária para gravar e ditar.',
    RbPermission.screenRecording => 'Necessária para o áudio do sistema.',
    RbPermission.accessibility => 'Necessária para colar o ditado.',
  };
}

/// Rótulos legíveis dos modelos whisper (o enum do plugin não os carrega).
extension WhisperModelLabel on WhisperModel {
  String get label => switch (this) {
    WhisperModel.largeV3TurboQ5 => 'Large v3 Turbo (q5)',
    WhisperModel.smallQ5 => 'Small (q5)',
  };
}
