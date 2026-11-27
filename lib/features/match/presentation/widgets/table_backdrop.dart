import 'package:flutter/material.dart';

/// The night table (flat) with a faint scattered-dice pattern.
class TableBackdrop extends CustomPainter {
  const TableBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0B1120));
    final tile = Paint()..color = Colors.white.withValues(alpha: 0.028);
    final pip = Paint()..color = Colors.white.withValues(alpha: 0.04);
    const step = 74.0;
    canvas.save();
    canvas.rotate(-0.35);
    for (var y = -size.height; y < size.height * 1.6; y += step) {
      for (var x = -size.width; x < size.width * 1.6; x += step) {
        final offset = ((y / step).round().isEven) ? 0.0 : step / 2;
        final r = Rect.fromLTWH(x + offset, y, 34, 34);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), tile);
        canvas.drawCircle(r.center, 3.2, pip);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TableBackdrop oldDelegate) => false;
}
