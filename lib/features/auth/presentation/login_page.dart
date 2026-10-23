import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';
import 'package:rbnotes/core/ui/pulse_dot.dart';
import 'package:rbnotes/core/ui/traffic_lights.dart';
import 'package:rbnotes/core/ui/wave_bars.dart';
import 'package:rbnotes/features/auth/presentation/login_cubit.dart';

/// Tela de login/cadastro, fiel ao design v3 (painel esquerdo com a frase
/// serif e o card "Gravando" animado; direita com Apple/Google/e-mail+senha).
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Material(
      color: rb.bg2,
      child: const Row(
        children: [
          SizedBox(width: 560, child: _LeftPanel()),
          Expanded(child: _RightPanel()),
        ],
      ),
    );
  }
}

class _LeftPanel extends StatelessWidget {
  const _LeftPanel();

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      decoration: BoxDecoration(
        color: rb.warm,
        border: Border(right: BorderSide(color: rb.hairline, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(56, 18, 56, 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16, child: TrafficLights()),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Fale à vontade. O RbNotes escreve, resume e '
                  'lembra por você.',
                  style: context.serif(
                    size: 40,
                    weight: FontWeight.w400,
                    height: 1.12,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 36),
                const _RecordingCard(),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              'A transcrição roda no seu Mac com Whisper. O áudio nunca sai '
              'do seu computador.',
              style: context.bodyText(
                size: 12,
                height: 1.5,
                color: rb.secondary(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -1.2 * 3.1415926 / 180,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E3C2814),
              blurRadius: 40,
              offset: Offset(0, 20),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PulseDot(color: Color(0xFFFF453A)),
                const SizedBox(width: 9),
                Text(
                  'Gravando',
                  style: context.bodyText(
                    size: 12,
                    weight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                Text(
                  '0:14',
                  style: context
                      .bodyText(
                        size: 17,
                        color: Colors.white,
                      )
                      .copyWith(fontFeatures: const []),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: LiveWaveBars(
                count: 64,
                maxHeight: 36,
                colorFor: (i, n) =>
                    Colors.white.withValues(alpha: 0.25 + 0.75 * i / (n - 1)),
              ),
            ),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text:
                        '…a ideia é testar o protótipo com cinco pessoas '
                        'antes de sexta ',
                  ),
                  TextSpan(
                    text: 'e ajustar o fluxo',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
              style: context.bodyText(
                size: 14,
                height: 1.55,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: SizedBox(width: 320, child: _AuthForm()),
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm();

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return BlocBuilder<LoginCubit, LoginState>(
      builder: (context, state) {
        final cubit = context.read<LoginCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BrandMark(size: 56, radius: 14, fontSize: 24),
            const SizedBox(height: 22),
            Text(
              state.isSignup ? 'Crie sua conta' : 'Entre na sua conta',
              style: context.bodyText(
                size: 22,
                weight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Suas notas sincronizadas entre todos os seus Macs.',
              style: context.bodyText(
                size: 13,
                height: 1.45,
                color: rb.secondary(0.65),
              ),
            ),
            const SizedBox(height: 26),
            const Tooltip(
              message: 'Em breve',
              child: Opacity(
                opacity: 0.5,
                child: _SocialButton(
                  label: 'Continuar com a Apple',
                  background: Colors.black,
                  foreground: Colors.white,
                  leading: Text(
                    '',
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _SocialButton(
              label: 'Continuar com Google',
              background: rb.card,
              foreground: rb.text,
              bordered: true,
              onTap: state.loading ? null : cubit.signInWithGoogle,
              leading: const Text(
                'G',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const _OrDivider(),
            const SizedBox(height: 20),
            if (state.isSignup) ...[
              _AuthField(
                hint: 'Nome',
                value: state.name,
                onChanged: cubit.setName,
              ),
              const SizedBox(height: 8),
            ],
            _AuthField(
              hint: 'E-mail',
              value: state.email,
              onChanged: cubit.setEmail,
            ),
            const SizedBox(height: 8),
            _AuthField(
              hint: 'Senha',
              value: state.password,
              obscure: true,
              onChanged: cubit.setPassword,
              onSubmitted: (_) => cubit.submit(),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: context.bodyText(
                  size: 12,
                  color: const Color(0xFFD70015),
                ),
              ),
            ],
            const SizedBox(height: 6),
            _PrimaryButton(
              label: state.loading
                  ? (state.isSignup ? 'Criando conta…' : 'Entrando…')
                  : (state.isSignup ? 'Criar conta' : 'Entrar'),
              onTap: state.loading ? null : cubit.submit,
            ),
            if (!state.isSignup) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Esqueceu a senha?',
                  style: context.bodyText(size: 12, color: rb.accent),
                ),
              ),
            ],
            const SizedBox(height: 30),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: rb.hairline, width: 0.5)),
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    state.isSignup
                        ? 'Já tem uma conta? '
                        : 'Não tem uma conta? ',
                    style: context.bodyText(
                      size: 12.5,
                      color: rb.secondary(0.65),
                    ),
                  ),
                  GestureDetector(
                    onTap: cubit.toggleMode,
                    child: Text(
                      state.isSignup ? 'Entrar' : 'Criar conta',
                      style: context.bodyText(
                        size: 12.5,
                        weight: FontWeight.w600,
                        color: rb.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'Ao continuar, você concorda com os Termos de Uso e a '
                'Política de Privacidade.',
                textAlign: TextAlign.center,
                style: context.bodyText(
                  size: 11,
                  height: 1.5,
                  color: rb.secondary(0.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// O "logo" RbNotes: quadrado escuro com "Rb" serif e o ponto de acento.
class _BrandMark extends StatelessWidget {
  const _BrandMark({
    required this.size,
    required this.radius,
    required this.fontSize,
  });

  final double size;
  final double radius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
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
              borderRadius: BorderRadius.circular(radius),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2E000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              'Rb',
              style: context.serif(
                size: fontSize,
                letterSpacing: -0.5,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: size * 0.18,
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

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.leading,
    this.bordered = false,
    this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Widget leading;
  final bool bordered;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(9),
          border: bordered
              ? Border.all(color: rb.onSurface(0.2), width: 0.5)
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 8),
            Text(
              label,
              style: context.bodyText(
                size: 13.5,
                weight: FontWeight.w500,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Row(
      children: [
        Expanded(child: Container(height: 0.5, color: rb.hairline)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'ou',
            style: context.bodyText(size: 11.5, color: rb.secondary(0.5)),
          ),
        ),
        Expanded(child: Container(height: 0.5, color: rb.hairline)),
      ],
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.hint,
    required this.value,
    required this.onChanged,
    this.obscure = false,
    this.onSubmitted,
  });

  final String hint;
  final String value;
  final bool obscure;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Container(
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: rb.fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rb.onSurface(0.22), width: 0.5),
      ),
      child: TextFormField(
        initialValue: value,
        obscureText: obscure,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        style: context.bodyText(size: 13.5),
        cursorColor: rb.accent,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: context.bodyText(size: 13.5, color: rb.secondary(0.45)),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: rb.accent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: context.bodyText(
            size: 13.5,
            weight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
