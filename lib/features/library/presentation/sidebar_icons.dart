import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Ícones da sidebar desenhados com [CustomPaint], fiéis aos glifos do design
/// v3 (`◉`, `★`, `◐`, `◇`). Usamos vetores em vez de glifos de fonte porque
/// Inter/Newsreader não têm esses caracteres (apareciam como barras "tofu").
enum SidebarIcon {
  /// Todas as notas — círculo com anel (`◉`).
  allNotes,

  /// Favoritas — estrela (`★`).
  favorites,

  /// Diário — meio-círculo (`◐`).
  diary,

  /// Coleções inteligentes — losango vazado (`◇`).
  collection,
}

/// Desenha [icon] em [color], centrado num quadrado de [size].
class SidebarGlyph extends StatelessWidget {
  const SidebarGlyph({
    required this.icon,
    required this.color,
    this.size = 13,
    super.key,
  });

  final SidebarIcon icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SidebarIconPainter(icon: icon, color: color),
      ),
    );
  }
}

class _SidebarIconPainter extends CustomPainter {
  const _SidebarIconPainter({required this.icon, required this.color});

  final SidebarIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    switch (icon) {
      case SidebarIcon.allNotes:
        _paintAllNotes(canvas, center, r);
      case SidebarIcon.favorites:
        _paintStar(canvas, center, r);
      case SidebarIcon.diary:
        _paintDiary(canvas, center, r);
      case SidebarIcon.collection:
        _paintDiamond(canvas, center, r);
    }
  }

  /// `◉` — anel externo + ponto cheio no centro.
  void _paintAllNotes(Canvas canvas, Offset center, double r) {
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.26;
    canvas.drawCircle(center, r * 0.86, ring);
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r * 0.34, dot);
  }

  /// `◐` — círculo com a metade esquerda cheia e a direita só contornada.
  void _paintDiary(Canvas canvas, Offset center, double r) {
    final radius = r * 0.86;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Metade esquerda preenchida (de 90° a 270°).
    canvas.drawArc(rect, math.pi / 2, math.pi, true, fill);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.22;
    canvas.drawCircle(center, radius, stroke);
  }

  /// `★` — estrela de cinco pontas preenchida.
  void _paintStar(Canvas canvas, Offset center, double r) {
    final path = Path();
    const points = 5;
    final outer = r * 0.98;
    final inner = outer * 0.42;
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / points;
      final p = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// `◇` — losango vazado (apenas contorno).
  void _paintDiamond(Canvas canvas, Offset center, double r) {
    final d = r * 0.9;
    final path = Path()
      ..moveTo(center.dx, center.dy - d)
      ..lineTo(center.dx + d, center.dy)
      ..lineTo(center.dx, center.dy + d)
      ..lineTo(center.dx - d, center.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.24
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SidebarIconPainter old) =>
      old.icon != icon || old.color != color;
}
