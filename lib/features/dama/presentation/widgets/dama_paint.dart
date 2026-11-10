import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';

/// Dama's look: a coffee-house board in warm walnut and honey maple, ivory and
/// ebony pieces with a gold rim, and a woven border band (original pattern,
/// inspired by the geometric borders of hand-woven cloth). All drawn in code.
abstract final class DamaPalette {
  static const tableTop = Color(0xFF2A170C);
  static const tableBottom = Color(0xFF140A05);
  static const frame = Color(0xFF4A2511);
  static const frameEdge = Color(0xFF2B1407);
  static const gold = Color(0xFFD4A23C);
  static const goldLight = Color(0xFFF2CF7A);
  static const ochre = Color(0xFFB5652A);
  static const green = Color(0xFF2E7D4F);
  static const lightSquare = Color(0xFFE8C78E);
  static const darkSquare = Color(0xFF6B3A1C);
  static const darkSquareGrain = Color(0xFF7C4524);
  static const ivory = Color(0xFFF4E9D2);
  static const ivoryShade = Color(0xFFC9B48C);
  static const ebony = Color(0xFF33251D);
  static const ebonyShade = Color(0xFF0F0907);
  static const target = Color(0xFFFFD54A);
  static const mustCapture = Color(0xFFFF7A45);
  static const lastMove = Color(0x55FFC94A);
}

/// Board-to-screen mapping: the viewer's own pieces are always at the bottom.
class DamaBoardGeometry {
  const DamaBoardGeometry({required this.size, required this.flipped});
  final double size;

  /// True when the viewer plays Dark (the board is turned 180°).
  final bool flipped;

  double get frame => size * 0.055;
  double get cell => (size - frame * 2) / 8;

  Rect squareRect(int square) {
    final row = damaRow(square);
    final col = damaCol(square);
    final displayRow = flipped ? row : 7 - row;
    final displayCol = flipped ? 7 - col : col;
    return Rect.fromLTWH(frame + displayCol * cell, frame + displayRow * cell, cell, cell);
  }

  Offset center(int square) => squareRect(square).center;

  /// Square under a touch point, or null outside the playing area.
  int? squareAt(Offset point) {
    final x = point.dx - frame;
    final y = point.dy - frame;
    if (x < 0 || y < 0) return null;
    final displayCol = (x / cell).floor();
    final displayRow = (y / cell).floor();
    if (displayCol > 7 || displayRow > 7) return null;
    final row = flipped ? displayRow : 7 - displayRow;
    final col = flipped ? 7 - displayCol : displayCol;
    return row * 8 + col;
  }
}

/// Frame, woven band and squares.
void paintDamaBoard(Canvas canvas, DamaBoardGeometry g) {
  final outer = RRect.fromRectAndRadius(Offset.zero & Size.square(g.size), Radius.circular(g.size * 0.03));
  canvas.drawRRect(
    outer,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF6A3618), DamaPalette.frame, DamaPalette.frameEdge],
      ).createShader(outer.outerRect),
  );
  _paintWovenBand(canvas, g);

  final light = Paint()..color = DamaPalette.lightSquare;
  final dark = Paint()..color = DamaPalette.darkSquare;
  final grain = Paint()
    ..color = DamaPalette.darkSquareGrain
    ..strokeWidth = g.cell * 0.02
    ..style = PaintingStyle.stroke;
  for (var square = 0; square < 64; square++) {
    final rect = g.squareRect(square);
    final playable = (damaRow(square) + damaCol(square)).isEven;
    canvas.drawRect(rect, playable ? dark : light);
    if (playable) {
      // A few soft grain lines so the walnut does not look flat.
      for (var i = 1; i <= 3; i++) {
        final y = rect.top + rect.height * (i / 4) + math.sin(square + i) * rect.height * 0.04;
        canvas.drawLine(Offset(rect.left + rect.width * 0.08, y), Offset(rect.right - rect.width * 0.08, y + rect.height * 0.03), grain);
      }
    }
  }
  final inner = Rect.fromLTWH(g.frame, g.frame, g.cell * 8, g.cell * 8);
  canvas.drawRect(
    inner,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.size * 0.006
      ..color = DamaPalette.gold,
  );
}

/// A band of small diamonds (gold, ochre, green) around the playing area.
void _paintWovenBand(Canvas canvas, DamaBoardGeometry g) {
  final mid = g.frame / 2;
  final step = g.frame * 0.62;
  final half = g.frame * 0.2;
  // Same rhythm on every side: gold, green, gold, ochre…
  const colors = [DamaPalette.gold, DamaPalette.green, DamaPalette.gold, DamaPalette.ochre];
  final paint = Paint();
  void diamond(Offset c, int index) {
    paint.color = colors[index % colors.length].withValues(alpha: 0.9);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - half)
        ..lineTo(c.dx + half, c.dy)
        ..lineTo(c.dx, c.dy + half)
        ..lineTo(c.dx - half, c.dy)
        ..close(),
      paint,
    );
  }

  // Evenly spaced from corner to corner, so opposite sides mirror each other.
  final span = g.size - g.frame;
  final count = ((span - mid) / step).floor();
  final gap = (span - mid) / count;
  for (var i = 0; i <= count; i++) {
    final t = mid + i * gap;
    diamond(Offset(t, mid), i);
    diamond(Offset(t, g.size - mid), i);
    if (i > 0 && i < count) {
      diamond(Offset(mid, t), i);
      diamond(Offset(g.size - mid, t), i);
    }
  }
}

/// One piece: shadow, turned-wood disc, gold rim and groove. A king is a
/// stacked double piece with a gold crown, as kings are crowned at the table.
void paintDamaPiece(
  Canvas canvas,
  Offset center,
  double radius,
  DamaPiece piece, {
  double opacity = 1,
  double lift = 0,
}) {
  if (opacity <= 0) return;
  final light = piece.color == DamaColor.light;
  final base = light ? DamaPalette.ivory : DamaPalette.ebony;
  final shade = light ? DamaPalette.ivoryShade : DamaPalette.ebonyShade;
  Color fade(Color c) => c.withValues(alpha: c.a * opacity);

  canvas.drawOval(
    Rect.fromCenter(center: center + Offset(0, radius * (0.22 + lift * 0.4)), width: radius * 2.05, height: radius * 1.5),
    Paint()
      ..color = fade(Colors.black.withValues(alpha: 0.38 - lift * 0.12))
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * (0.18 + lift * 0.3)),
  );

  void disc(Offset c) {
    final rect = Rect.fromCircle(center: c, radius: radius);
    // Edge (the side of the disc) then the face.
    canvas.drawCircle(c + Offset(0, radius * 0.12), radius, Paint()..color = fade(shade));
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.05,
          colors: [fade(Color.lerp(base, Colors.white, 0.25)!), fade(base), fade(shade)],
          stops: const [0, 0.6, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      radius * 0.93,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.1
        ..color = fade(DamaPalette.gold),
    );
    canvas.drawCircle(
      c,
      radius * 0.58,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.06
        ..color = fade(shade.withValues(alpha: 0.7)),
    );
  }

  final top = center - Offset(0, radius * lift * 0.25);
  if (piece.king) {
    disc(top + Offset(0, radius * 0.16));
    final crowned = top - Offset(0, radius * 0.14);
    disc(crowned);
    paintCrown(canvas, crowned, radius * 0.62, opacity: opacity);
  } else {
    disc(top);
  }
}

/// A small three-point crown (also used for the hub art and seats).
void paintCrown(Canvas canvas, Offset center, double width, {double opacity = 1}) {
  final w = width;
  final h = width * 0.72;
  final left = center.dx - w / 2;
  final top = center.dy - h / 2;
  final path = Path()
    ..moveTo(left, top + h)
    ..lineTo(left, top + h * 0.35)
    ..lineTo(left + w * 0.25, top + h * 0.62)
    ..lineTo(left + w * 0.5, top)
    ..lineTo(left + w * 0.75, top + h * 0.62)
    ..lineTo(left + w, top + h * 0.35)
    ..lineTo(left + w, top + h)
    ..close();
  canvas.drawPath(
    path,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          DamaPalette.goldLight.withValues(alpha: opacity),
          DamaPalette.gold.withValues(alpha: opacity),
        ],
      ).createShader(path.getBounds()),
  );
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..color = const Color(0xFF7A5414).withValues(alpha: opacity),
  );
}

/// Hub/lobby art: a corner of the board with a few pieces and a king.
class DamaBoardArt extends StatelessWidget {
  const DamaBoardArt({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _DamaArtPainter(), size: Size.infinite);
}

class _DamaArtPainter extends CustomPainter {
  const _DamaArtPainter();

  static const _pieces = {
    0: DamaPiece(DamaColor.light),
    2: DamaPiece(DamaColor.light),
    9: DamaPiece(DamaColor.light, king: true),
    18: DamaPiece(DamaColor.dark),
    27: DamaPiece(DamaColor.dark),
    25: DamaPiece(DamaColor.dark, king: true),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    // Only the 4×4 corner of an 8×8 board is shown, zoomed in.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(0, -s);
    final g = DamaBoardGeometry(size: s * 2, flipped: false);
    paintDamaBoard(canvas, g);
    for (final entry in _pieces.entries) {
      paintDamaPiece(canvas, g.center(entry.key), g.cell * 0.38, entry.value);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DamaArtPainter oldDelegate) => false;
}
