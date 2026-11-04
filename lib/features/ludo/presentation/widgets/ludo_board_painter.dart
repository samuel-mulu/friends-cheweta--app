import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';

/// Static classic board: colored yards with white insets and token slots,
/// colored home lanes, start squares with direction arrows, starred safe
/// squares, and the four-triangle home. Tokens are painted in a separate
/// layer, so this is drawn once (shouldRepaint is false).
class LudoBoardPainter extends CustomPainter {
  const LudoBoardPainter();

  static const _cell = Color(0xFFFFFFFF);
  static const _grid = Color(0xFFCBD2DC);
  static const _frame = Color(0xFF0E1A2B);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / LudoBoardGeometry.gridSize;
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, cell * 0.04)
      ..color = _grid;
    final fill = Paint();

    final board = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.3));
    canvas.drawRRect(board, Paint()..color = _cell);

    _yard(canvas, cell, 0, 0, LudoColor.red);
    _yard(canvas, cell, 9, 0, LudoColor.green);
    _yard(canvas, cell, 9, 9, LudoColor.yellow);
    _yard(canvas, cell, 0, 9, LudoColor.blue);

    // Track and home lanes.
    final laneColor = <String, Color>{
      for (final entry in LudoBoardGeometry.homePaths.entries)
        for (final grid in entry.value) '${grid.row}:${grid.column}': entry.key.color,
    };
    for (final grid in [...LudoBoardGeometry.track, for (final lane in LudoBoardGeometry.homePaths.values) ...lane]) {
      final rect = Rect.fromLTWH(grid.column * cell, grid.row * cell, cell, cell);
      fill.color = laneColor['${grid.row}:${grid.column}'] ?? _cell;
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, gridPaint);
    }

    // Start squares: owner color + arrow pointing along the direction of play.
    for (final color in LudoColor.values) {
      final from = LudoBoardGeometry.track[color.startIndex];
      final to = LudoBoardGeometry.track[(color.startIndex + 1) % 52];
      final rect = Rect.fromLTWH(from.column * cell, from.row * cell, cell, cell);
      canvas.drawRect(rect, fill..color = color.color);
      canvas.drawRect(rect, gridPaint);
      _arrow(canvas, rect.center, Offset((to.column - from.column).toDouble(), (to.row - from.row).toDouble()), cell);
    }

    // Safe squares (not starts): star in the color of that arm.
    for (final index in LudoBoardGeometry.safeGlobalSquares) {
      if (index % 13 == 0) continue;
      final grid = LudoBoardGeometry.track[index];
      final owner = LudoColor.values[(index ~/ 13) % 4];
      final center = Offset((grid.column + .5) * cell, (grid.row + .5) * cell);
      canvas.drawPath(_star(center, cell * 0.34, cell * 0.15), fill..color = owner.color);
    }

    _home(canvas, cell);

    canvas.drawRRect(
      board.deflate(cell * 0.03),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, cell * 0.08)
        ..color = _frame.withValues(alpha: 0.85),
    );
  }

  void _yard(Canvas canvas, double cell, int col, int row, LudoColor color) {
    final outer = Rect.fromLTWH(col * cell, row * cell, 6 * cell, 6 * cell);
    canvas.drawRect(outer, Paint()..color = color.color);
    // Subtle top-light so the yard does not look flat.
    canvas.drawRect(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.16), Colors.transparent, Colors.black.withValues(alpha: 0.08)],
        ).createShader(outer),
    );

    final inset = RRect.fromRectAndRadius(
      Rect.fromLTWH((col + 1) * cell, (row + 1) * cell, 4 * cell, 4 * cell),
      Radius.circular(cell * 0.4),
    );
    canvas.drawRRect(inset.shift(Offset(0, cell * 0.06)), Paint()..color = Colors.black.withValues(alpha: 0.12));
    canvas.drawRRect(inset, Paint()..color = _cell);

    // Token slots (same centers the geometry uses for tokens at base).
    for (final local in const [Offset(1.8, 1.8), Offset(4.2, 1.8), Offset(1.8, 4.2), Offset(4.2, 4.2)]) {
      final center = Offset((col + local.dx) * cell, (row + local.dy) * cell);
      canvas.drawCircle(center, cell * 0.5, Paint()..color = color.color);
      canvas.drawCircle(
        center,
        cell * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.07
          ..color = color.deepColor,
      );
    }
  }

  void _home(Canvas canvas, double cell) {
    final l = 6 * cell, t = 6 * cell, r = 9 * cell, b = 9 * cell;
    final c = Offset(7.5 * cell, 7.5 * cell);
    final triangles = <(LudoColor, List<Offset>)>[
      (LudoColor.red, [Offset(l, t), Offset(l, b), c]),
      (LudoColor.green, [Offset(l, t), Offset(r, t), c]),
      (LudoColor.yellow, [Offset(r, t), Offset(r, b), c]),
      (LudoColor.blue, [Offset(l, b), Offset(r, b), c]),
    ];
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, cell * 0.05)
      ..color = Colors.white.withValues(alpha: 0.9);
    for (final (color, points) in triangles) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, Paint()..color = color.color);
      canvas.drawPath(path, edge);
    }
  }

  void _arrow(Canvas canvas, Offset center, Offset direction, double cell) {
    final d = direction / direction.distance;
    final n = Offset(-d.dy, d.dx);
    final tip = center + d * cell * 0.28;
    final back = center - d * cell * 0.22;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((back + n * cell * 0.2).dx, (back + n * cell * 0.2).dy)
      ..lineTo((center - d * cell * 0.08).dx, (center - d * cell * 0.08).dy)
      ..lineTo((back - n * cell * 0.2).dx, (back - n * cell * 0.2).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  Path _star(Offset center, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = center + Offset(radius * math.cos(angle), radius * math.sin(angle));
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) => false;
}
