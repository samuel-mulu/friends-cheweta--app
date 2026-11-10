import 'package:flutter/material.dart';

const _gold = Color(0xFFFFC83D);
const _goldDeep = Color(0xFFE09A12);

/// A small king's crown. [filled] = earned (gold); otherwise an outline slot.
class CrownIcon extends StatelessWidget {
  const CrownIcon({super.key, this.size = 18, this.filled = true, this.color});
  final double size;
  final bool filled;

  /// Outline color for an empty slot (defaults to a soft white).
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * 0.8,
        child: CustomPaint(painter: _CrownPainter(filled: filled, outline: color ?? Colors.white.withValues(alpha: 0.45))),
      );
}

/// [count] crowns, the first [filled] of them gold ("2 of 3 home").
class CrownRow extends StatelessWidget {
  const CrownRow({super.key, required this.count, this.filled, this.size = 16, this.spacing = 2, this.emptyColor});
  final int count;

  /// Defaults to all filled.
  final int? filled;
  final double size;
  final double spacing;
  final Color? emptyColor;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing / 2),
              child: CrownIcon(size: size, filled: i < (filled ?? count), color: emptyColor),
            ),
        ],
      );
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter({required this.filled, required this.outline});
  final bool filled;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Three-point crown on a band.
    final path = Path()
      ..moveTo(w * 0.08, h * 0.82)
      ..lineTo(w * 0.02, h * 0.28)
      ..lineTo(w * 0.3, h * 0.52)
      ..lineTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.7, h * 0.52)
      ..lineTo(w * 0.98, h * 0.28)
      ..lineTo(w * 0.92, h * 0.82)
      ..close();
    final band = Rect.fromLTRB(w * 0.08, h * 0.82, w * 0.92, h * 0.98);

    if (filled) {
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE27A), _gold, _goldDeep],
        ).createShader(Offset.zero & size);
      canvas.drawPath(path, paint);
      canvas.drawRect(band, Paint()..color = _goldDeep);
      // Jewels on the tips.
      final jewel = Paint()..color = Colors.white.withValues(alpha: 0.9);
      for (final x in [0.02, 0.5, 0.98]) {
        canvas.drawCircle(Offset(w * x, x == 0.5 ? h * 0.08 : h * 0.28), w * 0.07, jewel);
      }
    } else {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (w * 0.08).clamp(1.0, 2.5)
        ..strokeJoin = StrokeJoin.round
        ..color = outline;
      canvas.drawPath(path, stroke);
      canvas.drawRect(band, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CrownPainter old) => old.filled != filled || old.outline != outline;
}
