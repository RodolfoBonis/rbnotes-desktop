import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rbnotes/app/accent_cubit.dart';
import 'package:rbnotes/core/theme/accent_presets.dart';
import 'package:rbnotes/core/theme/color_contrast.dart';
import 'package:rbnotes/core/theme/rb_tokens.dart';

/// Row of preset accent swatches plus a "custom color" dot. Selecting one
/// applies it immediately through [AccentCubit] (the whole app theme rebuilds,
/// giving a live preview).
class AccentSwatches extends StatelessWidget {
  const AccentSwatches({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.watch<AccentCubit>().state;
    final selectedPreset = AccentPresets.forColor(current);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in AccentPresets.all)
          _Swatch(
            key: Key('accent-swatch-${preset.id}'),
            color: preset.color,
            selected: selectedPreset?.id == preset.id,
            tooltip: preset.label,
            onTap: () => context.read<AccentCubit>().selectPreset(preset),
          ),
        _CustomSwatch(
          key: const Key('accent-swatch-custom'),
          color: current,
          selected: selectedPreset == null,
          onTap: () => _openCustom(context, current),
        ),
      ],
    );
  }

  Future<void> _openCustom(BuildContext context, Color initial) async {
    final cubit = context.read<AccentCubit>();
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => CustomAccentDialog(initial: initial),
    );
    if (picked != null) await cubit.setColor(picked);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.tooltip,
    super.key,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final dot = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? rb.text : rb.onSurface(0.12),
            width: selected ? 2 : 0.5,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 15,
                color: ColorContrast.onColorFor(color),
              )
            : null,
      ),
    );
    final tip = tooltip;
    return tip == null ? dot : Tooltip(message: tip, child: dot);
  }
}

class _CustomSwatch extends StatelessWidget {
  const _CustomSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    return Tooltip(
      message: 'Cor personalizada',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: const SweepGradient(
              colors: [
                Color(0xFFE0512E),
                Color(0xFFCB8A16),
                Color(0xFF1E8C5A),
                Color(0xFF2F6BEB),
                Color(0xFF7A5AF0),
                Color(0xFFD64B8A),
                Color(0xFFE0512E),
              ],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? rb.text : rb.onSurface(0.12),
              width: selected ? 2 : 0.5,
            ),
          ),
          child: Icon(
            selected ? Icons.check : Icons.add,
            size: 15,
            color: selected ? color : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Custom accent picker: a hue slider + a saturation/brightness square, a hex
/// field, and a live AA-contrast check. Returns the chosen [Color] on "Usar".
class CustomAccentDialog extends StatefulWidget {
  const CustomAccentDialog({required this.initial, super.key});

  final Color initial;

  @override
  State<CustomAccentDialog> createState() => _CustomAccentDialogState();
}

class _CustomAccentDialogState extends State<CustomAccentDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(widget.initial),
  );

  Color get _color => _hsv.toColor();

  static String _hexOf(Color c) {
    final rgb = c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
    return '#${rgb.toUpperCase()}';
  }

  void _setHsv(HSVColor v) {
    setState(() {
      _hsv = v;
      _hex.text = _hexOf(v.toColor());
    });
  }

  void _applyHex(String raw) {
    final hex = raw.replaceAll('#', '').trim();
    if (hex.length != 6) return;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | value)));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rb = context.rb;
    final color = _color;
    // Contrast against both themes so the warning covers light and dark.
    final onWhite = ColorContrast.ratio(
      color,
      const Color(0xFFFFFFFF),
    );
    final onDark = ColorContrast.ratio(color, const Color(0xFF1E1E20));
    final buttonText = ColorContrast.ratio(
      ColorContrast.onColorFor(color),
      color,
    );
    final passesButton = buttonText >= ColorContrast.aaLarge;
    final passesText =
        onWhite >= ColorContrast.aaText || onDark >= ColorContrast.aaText;

    return AlertDialog(
      backgroundColor: rb.card,
      title: const Text('Cor personalizada'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SatValSquare(
              hsv: _hsv,
              onChanged: _setHsv,
            ),
            const SizedBox(height: 12),
            _HueSlider(
              hue: _hsv.hue,
              onChanged: (h) => _setHsv(_hsv.withHue(h)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: rb.onSurface(0.12), width: 0.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('accent-hex-field'),
                    controller: _hex,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(7),
                      FilteringTextInputFormatter.allow(RegExp('[#0-9a-fA-F]')),
                    ],
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Hex',
                    ),
                    onChanged: _applyHex,
                  ),
                ),
              ],
            ),
            if (!passesButton || !passesText) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: RbTokens.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      !passesButton
                          ? 'Texto nos botões pode ficar pouco legível '
                                '(contraste abaixo de AA).'
                          : 'Como texto de acento o contraste fica abaixo de '
                                'AA em um dos temas.',
                      style: context.bodyText(
                        size: 11.5,
                        height: 1.4,
                        color: RbTokens.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: const Key('accent-custom-apply'),
          onPressed: () => Navigator.of(context).pop(color),
          child: const Text('Usar'),
        ),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset local) {
          final x = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
          onChanged(x * 360);
        }

        return GestureDetector(
          onTapDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: Container(
            height: 18,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
              ),
            ),
            child: Align(
              alignment: Alignment((hue / 360) * 2 - 1, 0),
              child: Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SatValSquare extends StatelessWidget {
  const _SatValSquare({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        const h = 150.0;
        void update(Offset local) {
          final s = (local.dx / w).clamp(0.0, 1.0);
          final v = 1 - (local.dy / h).clamp(0.0, 1.0);
          onChanged(hsv.withSaturation(s).withValue(v));
        }

        return GestureDetector(
          onTapDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: SizedBox(
            height: h,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                gradient: const LinearGradient(
                  colors: [Colors.white, Colors.transparent],
                ),
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                  ),
                ),
                child: Align(
                  alignment: Alignment(
                    hsv.saturation * 2 - 1,
                    (1 - hsv.value) * 2 - 1,
                  ),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: RbTokens.scrim, blurRadius: 2),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
