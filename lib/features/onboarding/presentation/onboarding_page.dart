import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/pulse_dot.dart';
import 'package:rbnotes/core/ui/rb_lottie.dart';
import 'package:rbnotes/core/ui/traffic_lights.dart';
import 'package:rbnotes/features/onboarding/presentation/onboarding_cubit.dart';
import 'package:rbnotes/native/rb_native.dart';

/// Onboarding em 4 passos (boas-vindas, permissões, modelo, pronto).
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    required this.firstName,
    required this.onFinish,
    required this.onRecordFirst,
    super.key,
  });

  final String firstName;
  final VoidCallback onFinish;
  final VoidCallback onRecordFirst;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Material(
      color: rb.bg2,
      child: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          return Column(
            children: [
              _Header(step: state.step),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 20,
                    ),
                    child: SizedBox(
                      width: 560,
                      child: switch (state.step) {
                        0 => _Welcome(firstName: firstName),
                        1 => const _Permissions(),
                        2 => const _ModelStep(),
                        _ => _Ready(
                          onFinish: onFinish,
                          onRecordFirst: onRecordFirst,
                        ),
                      },
                    ),
                  ),
                ),
              ),
              if (state.step < 3) _Footer(state: state),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TrafficLights(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == step ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= step ? rb.accent : rb.onSurface(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandSquare extends StatelessWidget {
  const _BrandSquare();

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    const size = 64.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: rb.ink,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              'Rb',
              style: context.serif(
                size: size * 0.42,
                letterSpacing: -0.5,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: size * 0.19,
            bottom: size * 0.2,
            child: Container(
              width: size * 0.11,
              height: size * 0.11,
              decoration: BoxDecoration(
                color: rb.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.firstName});
  final String firstName;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BrandSquare(),
        const SizedBox(height: 26),
        Text(
          'Olá, $firstName.',
          style: context.serif(size: 38, weight: FontWeight.w500, height: 1.1),
        ),
        const SizedBox(height: 10),
        Text(
          'Em um minuto o RbNotes fica pronto. Antes, veja o caminho que cada '
          'nota faz.',
          style: context.bodyText(
            size: 15,
            height: 1.55,
            color: rb.secondary(0.72),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            const Expanded(
              child: _FlowCard(
                title: 'Sua voz',
                sub: 'Gravada pelo microfone do Mac',
              ),
            ),
            _arrow(context),
            const Expanded(
              child: _FlowCard(
                title: 'Whisper',
                sub: 'Transcreve no seu Mac, sem internet',
              ),
            ),
            _arrow(context),
            const Expanded(
              child: _FlowCard(
                title: 'Claude',
                sub: 'Recebe só o texto para resumir',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _arrow(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Text(
      '→',
      style: TextStyle(color: context.rb.secondary(0.4), fontSize: 16),
    ),
  );
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.title, required this.sub});
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.bodyText(size: 13.5, weight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: context.bodyText(
              size: 12,
              height: 1.4,
              color: rb.secondary(0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _Permissions extends StatelessWidget {
  const _Permissions();

  static const _defs = <(OnbPerm, String, String, String, IconData, bool)>[
    (
      OnbPerm.mic,
      'Microfone',
      'Obrigatória',
      'Para gravar suas notas de voz.',
      Icons.mic_none,
      true,
    ),
    (
      OnbPerm.screen,
      'Gravação de tela e áudio do sistema',
      'Opcional',
      'Para captar as outras vozes em chamadas no Meet, Zoom e Teams. '
          'Nenhuma imagem da tela é gravada.',
      Icons.desktop_windows_outlined,
      false,
    ),
    (
      OnbPerm.ax,
      'Acessibilidade',
      'Opcional',
      'Para o ditado global (⌥ Espaço) colar o texto em qualquer app.',
      Icons.accessibility_new,
      false,
    ),
    (
      OnbPerm.notif,
      'Notificações',
      'Opcional',
      'Para lembrar tarefas esquecidas e a pergunta do diário.',
      Icons.notifications_none,
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final state = context.watch<OnboardingCubit>().state;
    final cubit = context.read<OnboardingCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Permissões',
          style: context.serif(size: 32, weight: FontWeight.w500, height: 1.1),
        ),
        const SizedBox(height: 10),
        Text(
          'O macOS pede sua confirmação para cada uma. Você pode mudar depois '
          'em Ajustes do Sistema › Privacidade e Segurança.',
          style: context.bodyText(
            size: 14,
            height: 1.55,
            color: rb.secondary(0.72),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: rb.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: rb.onSurface(0.1), width: 0.5),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _defs.length; i++)
                _PermRow(
                  def: _defs[i],
                  status: state.permissions[_defs[i].$1]!,
                  topBorder: i > 0,
                  onTap: () => cubit.requestPermission(_defs[i].$1),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.def,
    required this.status,
    required this.topBorder,
    required this.onTap,
  });

  final (OnbPerm, String, String, String, IconData, bool) def;
  final PermState status;
  final bool topBorder;
  final VoidCallback onTap;

  /// Permissões pedidas dentro do app (macOS mostra o diálogo nativo):
  /// microfone e notificações. As demais só dá para abrir em Ajustes.
  bool get _inApp => def.$1 == OnbPerm.mic || def.$1 == OnbPerm.notif;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final required = def.$6;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: topBorder
            ? Border(top: BorderSide(color: rb.onSurface(0.08), width: 0.5))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: rb.accentWash(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(def.$5, size: 18, color: rb.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        def.$2,
                        style: context.bodyText(
                          size: 13.5,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: required ? rb.accentWash(0.14) : rb.controlFill,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        def.$3,
                        style: context.bodyText(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: required ? rb.accent : rb.secondary(0.75),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  def.$4,
                  style: context.bodyText(
                    size: 12,
                    height: 1.45,
                    color: rb.secondary(0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _permTrailing(context, required: required),
        ],
      ),
    );
  }

  Widget _permTrailing(BuildContext context, {required bool required}) {
    final rb = context.rb;
    switch (status) {
      case PermState.no:
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rb.controlFill,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              _inApp ? 'Permitir' : 'Abrir Ajustes',
              style: context.bodyText(size: 12.5, weight: FontWeight.w500),
            ),
          ),
        );
      case PermState.wait:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PulseDot(
              color: rb.accent,
              size: 6,
              period: const Duration(seconds: 1),
            ),
            const SizedBox(width: 7),
            Text(
              'Aguardando…',
              style: context.bodyText(size: 12, color: rb.secondary(0.65)),
            ),
          ],
        );
      case PermState.ok:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, size: 14, color: RbTokens.permitGreen),
            const SizedBox(width: 6),
            Text(
              'Permitido',
              style: context.bodyText(
                size: 12,
                weight: FontWeight.w600,
                color: RbTokens.permitGreen,
              ),
            ),
          ],
        );
    }
  }
}

class _ModelStep extends StatelessWidget {
  const _ModelStep();

  static const _models = <(WhisperModel, String, String, bool)>[
    (
      WhisperModel.smallQ5,
      'Small',
      '466 MB · rápido, bom para notas curtas',
      false,
    ),
    (
      WhisperModel.largeV3TurboQ5,
      'Large v3 Turbo',
      '1,6 GB · melhor equilíbrio no Apple Silicon',
      true,
    ),
    (
      WhisperModel.largeV3,
      'Large v3',
      '3,1 GB · máxima precisão, mais lento',
      false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final state = context.watch<OnboardingCubit>().state;
    final cubit = context.read<OnboardingCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modelo de transcrição',
          style: context.serif(size: 32, weight: FontWeight.w500, height: 1.1),
        ),
        const SizedBox(height: 10),
        Text(
          'O Whisper roda inteiro no seu Mac. Escolha um para começar; dá para '
          'trocar depois em Ajustes.',
          style: context.bodyText(
            size: 14,
            height: 1.55,
            color: rb.secondary(0.72),
          ),
        ),
        const SizedBox(height: 24),
        for (final m in _models)
          GestureDetector(
            onTap: () => cubit.selectModel(m.$1),
            behavior: HitTestBehavior.opaque,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: rb.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: state.model == m.$1 ? rb.accent : rb.onSurface(0.14),
                  width: state.model == m.$1 ? 1.5 : 0.5,
                ),
              ),
              child: Row(
                children: [
                  _Radio(selected: state.model == m.$1),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.$2,
                          style: context.bodyText(
                            size: 13.5,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          m.$3,
                          style: context.bodyText(
                            size: 12,
                            color: rb.secondary(0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (m.$4)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: rb.accentWash(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Recomendado',
                        style: context.bodyText(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: rb.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (state.downloading) ...[
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Baixando ${_models.firstWhere((m) => m.$1 == state.model).$2}',
                style: context.bodyText(size: 12, color: rb.secondary(0.7)),
              ),
              Text(
                '${((state.downloadProgress ?? 0) * 100).round()}%',
                style: context.bodyText(size: 12, color: rb.secondary(0.7)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: state.downloadProgress,
              minHeight: 5,
              backgroundColor: rb.controlFill,
              valueColor: AlwaysStoppedAnimation(rb.accent),
            ),
          ),
        ],
      ],
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.onFinish, required this.onRecordFirst});
  final VoidCallback onFinish;
  final VoidCallback onRecordFirst;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Column(
      children: [
        RbLottie(
          asset: 'assets/lottie/pulse.json',
          size: 56,
          recolor: rb.accent,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onRecordFirst,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: rb.accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: rb.accentWash(0.14),
                  spreadRadius: 10,
                ),
                BoxShadow(
                  color: rb.accentWash(0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 34),
        Text(
          'Tudo pronto.',
          style: context.serif(size: 36, weight: FontWeight.w500, height: 1.1),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(
            'Grave sua primeira nota agora. Pode ser qualquer coisa: '
            'uma ideia, o plano do dia, a lista do mercado.',
            textAlign: TextAlign.center,
            style: context.bodyText(
              size: 15,
              height: 1.55,
              color: rb.secondary(0.72),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Gravar de qualquer app:',
              style: context.bodyText(size: 12.5, color: rb.secondary(0.7)),
            ),
            const SizedBox(width: 8),
            const _Key('⌥'),
            const SizedBox(width: 4),
            const _Key('⇧'),
            const SizedBox(width: 4),
            const _Key('Espaço'),
          ],
        ),
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onFinish,
          behavior: HitTestBehavior.opaque,
          child: Text(
            'Explorar o app primeiro',
            style: context.bodyText(
              size: 13,
              weight: FontWeight.w500,
              color: rb.accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});
  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final cubit = context.read<OnboardingCubit>();
    final nextLabel = state.downloading
        ? 'Baixando…'
        : switch (state.step) {
            0 => 'Começar',
            1 => 'Continuar',
            _ => 'Baixar e continuar',
          };
    final dim = (state.step == 1 && !state.micGranted) || state.downloading;
    final hint = state.step == 1 && !state.micGranted
        ? 'O microfone é necessário para continuar.'
        : '';
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: rb.onSurface(0.08), width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Visibility(
            visible: state.step > 0 && !state.downloading,
            child: GestureDetector(
              onTap: cubit.back,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Voltar',
                style: context.bodyText(
                  size: 13,
                  weight: FontWeight.w500,
                  color: rb.secondary(0.75),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Text(
                hint,
                style: context.bodyText(size: 12, color: rb.secondary(0.6)),
              ),
              const SizedBox(width: 14),
              Opacity(
                opacity: dim ? 0.45 : 1,
                child: GestureDetector(
                  onTap: dim ? null : cubit.next,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rb.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      nextLabel,
                      style: context.bodyText(
                        size: 13,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: selected ? rb.accent : Colors.transparent,
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(color: rb.secondary(0.3), width: 1.5),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

class _Key extends StatelessWidget {
  const _Key(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: rb.onSurface(0.14), width: 0.5),
      ),
      child: Text(
        label,
        style: context.bodyText(size: 12, weight: FontWeight.w500),
      ),
    );
  }
}
