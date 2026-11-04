import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Brand colors shared by the logo and game art (same hues as the Ludo board).
abstract final class BrandColors {
  static const red = Color(0xFFE53935);
  static const green = Color(0xFF1FA35A);
  static const yellow = Color(0xFFF5B800);
  static const blue = Color(0xFF1E88E5);
  static const navy = Color(0xFF0B1530);
  static const gold = Color(0xFFFFC83D);
}

/// The app mark: a rounded tile split into the four Ludo colors with a tilted
/// white die in the middle whose corner pips carry the same colors.
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 56, this.square = false});

  final double size;

  /// Full-bleed square (launcher icons); otherwise rounded.
  final bool square;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: AppLogoPainter(square: square)));
}

class AppLogoPainter extends CustomPainter {
  const AppLogoPainter({this.square = false});
  final bool square;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(square ? 0 : s * 0.24));
    canvas.save();
    canvas.clipRRect(tile);

    final half = s / 2;
    final quadrants = [
      (Rect.fromLTWH(0, 0, half, half), BrandColors.red),
      (Rect.fromLTWH(half, 0, half, half), BrandColors.green),
      (Rect.fromLTWH(half, half, half, half), BrandColors.yellow),
      (Rect.fromLTWH(0, half, half, half), BrandColors.blue),
    ];
    for (final (rect, color) in quadrants) {
      canvas.drawRect(rect, Paint()..color = color);
    }
    // Soft light from the top-left so the tile has depth.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.22), Colors.transparent, Colors.black.withValues(alpha: 0.18)],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();

    // Die.
    final dieSize = s * 0.54;
    canvas.save();
    canvas.translate(half, half);
    canvas.rotate(-math.pi / 14);
    final die = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: dieSize, height: dieSize),
      Radius.circular(dieSize * 0.22),
    );
    canvas.drawRRect(die.shift(Offset(0, s * 0.03)), Paint()..color = Colors.black.withValues(alpha: 0.3));
    canvas.drawRRect(die, Paint()..color = Colors.white);
    canvas.drawRRect(
      die,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.018
        ..color = const Color(0xFFDDE3EA),
    );
    final d = dieSize * 0.25;
    final r = dieSize * 0.095;
    for (final (offset, color) in [
      (Offset(-d, -d), BrandColors.red),
      (Offset(d, -d), BrandColors.green),
      (Offset(d, d), BrandColors.yellow),
      (Offset(-d, d), BrandColors.blue),
      (Offset.zero, BrandColors.navy),
    ]) {
      canvas.drawCircle(offset, r, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AppLogoPainter oldDelegate) => oldDelegate.square != square;
}

/// Mark + wordmark. [light] for dark backgrounds.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48, this.light = false, this.vertical = false});

  final double size;
  final bool light;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final ink = light ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final word = Column(
      crossAxisAlignment: vertical ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FRIENDS',
          style: TextStyle(color: ink, fontSize: size * 0.46, fontWeight: FontWeight.w900, letterSpacing: size * 0.03, height: 1),
        ),
        SizedBox(height: size * 0.06),
        Text(
          'GAME HUB',
          style: TextStyle(
            color: light ? BrandColors.gold : const Color(0xFFC98A00),
            fontSize: size * 0.24,
            fontWeight: FontWeight.w800,
            letterSpacing: size * 0.08,
            height: 1,
          ),
        ),
      ],
    );
    final mark = AppLogoMark(size: size);
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [mark, SizedBox(height: size * 0.25), word])
        : Row(mainAxisSize: MainAxisSize.min, children: [mark, SizedBox(width: size * 0.25), word]);
  }
}
