import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Brand colors. Navy + gold carry the brand; the four game colors appear as
/// accents (tokens, glows) and are shared with the game art.
abstract final class BrandColors {
  static const red = Color(0xFFE53935);
  static const green = Color(0xFF1FA35A);
  static const yellow = Color(0xFFF5B800);
  static const blue = Color(0xFF1E88E5);
  static const navy = Color(0xFF0B1530);
  static const indigo = Color(0xFF1C2C6E);
  static const gold = Color(0xFFFFC83D);
}

/// The Friends mark: a bold white "F" on a navy tile with a fine gold ring.
/// Its two bars end in a red and a green game token — two players side by
/// side, game-neutral so it fits every game in the hub.
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 56, this.square = false, this.reveal = 1});

  final double size;

  /// Full-bleed square (launcher icons); otherwise rounded.
  final bool square;

  /// 0..1 draw-on progress (the splash animates it; 1 = complete).
  final double reveal;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: AppLogoPainter(square: square, reveal: reveal)),
      );
}

class AppLogoPainter extends CustomPainter {
  const AppLogoPainter({this.square = false, this.reveal = 1, this.tile = true});
  final bool square;
  final double reveal;

  /// False paints only the monogram (adaptive-icon foreground).
  final bool tile;

  /// Progress of one part of the reveal, 0..1 inside [start, end].
  double _part(double start, double end, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((reveal - start) / (end - start)).clamp(0.0, 1.0).toDouble());

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (tile) _paintTile(canvas, s);

    final stroke = s * 0.15;
    final ink = Paint()
      ..color = Colors.white
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final left = s * 0.35;
    final top = s * 0.29;
    final bottom = s * 0.73;
    final middle = s * 0.51;

    // A soft drop shadow under the letter for depth.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.02);

    // Stem grows upward, then the bars draw out to the right.
    final strokes = [
      (Offset(left, bottom), Offset(left, top), _part(0, 0.35)),
      (Offset(left, top), Offset(s * 0.60, top), _part(0.25, 0.55)),
      (Offset(left, middle), Offset(s * 0.53, middle), _part(0.4, 0.65)),
    ];
    // All shadows first, then all ink, so the letter reads as one shape.
    final drop = Offset(0, s * 0.02);
    for (final (a, b, t) in strokes) {
      if (t > 0) canvas.drawLine(a + drop, Offset.lerp(a, b, t)! + drop, shadow);
    }
    for (final (a, b, t) in strokes) {
      if (t > 0) canvas.drawLine(a, Offset.lerp(a, b, t)!, ink);
    }

    _token(canvas, Offset(s * 0.72, top), s * 0.085, BrandColors.red, _part(0.55, 0.85, Curves.elasticOut));
    _token(canvas, Offset(s * 0.65, middle), s * 0.075, BrandColors.green, _part(0.65, 0.95, Curves.elasticOut));
  }

  void _paintTile(Canvas canvas, double s) {
    final rect = Offset.zero & Size.square(s);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(square ? 0 : s * 0.26));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.indigo, BrandColors.navy],
        ).createShader(rect),
    );
    // Light from the top so the tile is not flat.
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawCircle(
      Offset(s * 0.2, -s * 0.1),
      s * 0.9,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.14), Colors.transparent])
            .createShader(Rect.fromCircle(center: Offset(s * 0.2, -s * 0.1), radius: s * 0.9)),
    );
    canvas.restore();
    // Fine gold ring (fades in with the reveal).
    final ringInset = s * 0.065;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(ringInset), Radius.circular(square ? s * 0.12 : s * 0.2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.016
        ..color = BrandColors.gold.withValues(alpha: 0.6 * _part(0.3, 1)),
    );
  }

  /// A glossy game token that pops in with [t] (elastic scale).
  void _token(Canvas canvas, Offset center, double radius, Color color, double t) {
    if (t <= 0) return;
    final r = radius * math.max(t, 0);
    canvas.drawCircle(center + Offset(0, radius * 0.25), r, Paint()..color = Colors.black.withValues(alpha: 0.28));
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(color, Colors.white, 0.35)!, color, Color.lerp(color, Colors.black, 0.25)!],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(covariant AppLogoPainter old) => old.square != square || old.reveal != reveal || old.tile != tile;
}

/// The wordmark: FRIENDS with the gold GAME HUB line under it.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.size = 48, this.light = false, this.center = false, this.tracking = 0});
  final double size;
  final bool light;
  final bool center;

  /// Extra letter spacing (the splash animates it closing in).
  final double tracking;

  @override
  Widget build(BuildContext context) {
    final ink = light ? Colors.white : Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'FRIENDS',
          style: TextStyle(
            color: ink,
            fontSize: size * 0.46,
            fontWeight: FontWeight.w900,
            letterSpacing: size * 0.04 + tracking,
            height: 1,
          ),
        ),
        SizedBox(height: size * 0.08),
        Text(
          'GAME HUB',
          style: TextStyle(
            color: light ? BrandColors.gold : const Color(0xFFC98A00),
            fontSize: size * 0.22,
            fontWeight: FontWeight.w800,
            letterSpacing: size * 0.1 + tracking * 0.5,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Mark + wordmark. [light] for dark backgrounds.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 48, this.light = false, this.vertical = false});

  final double size;
  final bool light;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final mark = AppLogoMark(size: size);
    final word = AppWordmark(size: size, light: light, center: vertical);
    return Semantics(
      label: 'Friends Game Hub',
      child: ExcludeSemantics(
        child: vertical
            ? Column(mainAxisSize: MainAxisSize.min, children: [mark, SizedBox(height: size * 0.25), word])
            : Row(mainAxisSize: MainAxisSize.min, children: [mark, SizedBox(width: size * 0.25), word]),
      ),
    );
  }
}
