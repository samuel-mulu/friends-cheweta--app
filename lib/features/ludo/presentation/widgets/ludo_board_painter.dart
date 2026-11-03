import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';

/// Static board surface. Tokens are painted in a separate overlay layer.
class LudoBoardPainter extends CustomPainter {
  const LudoBoardPainter();

  // Traditional board surface — stays light even in dark app chrome.
  static const _surface = Color(0xFFF7F3EA);
  static const _pathFill = Color(0xFFFFFDF8);
  static const _line = Color(0xFFB8B0A2);
  static const _frame = Color(0xFF8F8678);
  static const _innerShade = Color(0xFFE8E1D4);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / LudoBoardGeometry.gridSize;
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, cell * 0.045)
      ..color = _line.withValues(alpha: 0.85);

    // Board base with subtle depth
    final boardRRect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.35));
    canvas.drawRRect(boardRRect, Paint()..color = _surface);
    canvas.drawRRect(
      boardRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.35),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.04),
          ],
        ).createShader(Offset.zero & size),
    );

    _drawBase(canvas, cell, const Rect.fromLTWH(0, 0, 6, 6), LudoColor.red.color, fill, stroke);
    _drawBase(canvas, cell, const Rect.fromLTWH(9, 0, 6, 6), LudoColor.green.color, fill, stroke);
    _drawBase(canvas, cell, const Rect.fromLTWH(9, 9, 6, 6), LudoColor.yellow.color, fill, stroke);
    _drawBase(canvas, cell, const Rect.fromLTWH(0, 9, 6, 6), LudoColor.blue.color, fill, stroke);

    final trackSet = <String>{for (final grid in LudoBoardGeometry.track) '${grid.row}:${grid.column}'};
    final homeColors = <String, Color>{};
    for (final entry in LudoBoardGeometry.homePaths.entries) {
      for (final grid in entry.value) {
        homeColors['${grid.row}:${grid.column}'] = entry.key.color;
      }
    }

    for (var row = 0; row < 15; row++) {
      for (var col = 0; col < 15; col++) {
        final key = '$row:$col';
        if (!trackSet.contains(key) && !homeColors.containsKey(key)) continue;
        final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
        final home = homeColors[key];
        if (home != null) {
          fill.color = home.withValues(alpha: 0.78);
        } else {
          fill.color = _pathFill;
        }
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, stroke);
      }
    }

    // Colored start squares
    for (final color in LudoColor.values) {
      final start = LudoBoardGeometry.track[color.startIndex];
      final rect = Rect.fromLTWH(start.column * cell, start.row * cell, cell, cell);
      fill.color = color.color.withValues(alpha: 0.88);
      canvas.drawRRect(RRect.fromRectAndRadius(rect.deflate(cell * 0.06), Radius.circular(cell * 0.12)), fill);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(cell * 0.06), Radius.circular(cell * 0.12)),
        stroke..color = Colors.white.withValues(alpha: 0.55),
      );
      stroke.color = _line.withValues(alpha: 0.85);
    }

    // Safe markers
    for (final index in LudoBoardGeometry.safeGlobalSquares) {
      final grid = LudoBoardGeometry.track[index];
      final center = Offset((grid.column + .5) * cell, (grid.row + .5) * cell);
      final isStart = index % 13 == 0;
      if (isStart) continue; // start squares already colored
      _drawSafeMark(canvas, center, cell, fill);
    }

    _drawCenter(canvas, cell, fill, stroke);

    // Outer frame
    canvas.drawRRect(
      boardRRect.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, cell * 0.08)
        ..color = _frame.withValues(alpha: 0.75),
    );
  }

  void _drawBase(
    Canvas canvas,
    double cell,
    Rect gridRect,
    Color color,
    Paint fill,
    Paint stroke,
  ) {
    final rect = Rect.fromLTWH(gridRect.left * cell, gridRect.top * cell, gridRect.width * cell, gridRect.height * cell);
    fill.color = color.withValues(alpha: 0.92);
    canvas.drawRect(rect, fill);

    // Inner contrast band
    final band = rect.deflate(cell * 0.12);
    fill.color = Color.lerp(color, Colors.black, 0.12)!.withValues(alpha: 0.25);
    canvas.drawRect(band, fill);

    final inner = Rect.fromLTWH(
      (gridRect.left + 1) * cell,
      (gridRect.top + 1) * cell,
      4 * cell,
      4 * cell,
    );
    final innerR = RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.55));
    fill.color = _pathFill;
    canvas.drawRRect(innerR, fill);
    canvas.drawRRect(
      innerR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, cell * 0.06)
        ..color = color.withValues(alpha: 0.55),
    );

    // Subtle inner shade for depth
    canvas.drawRRect(
      innerR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            _innerShade.withValues(alpha: 0.45),
          ],
        ).createShader(inner),
    );

    const localCenters = <Offset>[
      Offset(1.8, 1.8),
      Offset(4.2, 1.8),
      Offset(1.8, 4.2),
      Offset(4.2, 4.2),
    ];
    for (final point in localCenters) {
      final center = Offset((gridRect.left + point.dx) * cell, (gridRect.top + point.dy) * cell);
      fill.color = color.withValues(alpha: 0.14);
      canvas.drawCircle(center, cell * 0.46, fill);
      canvas.drawCircle(
        center,
        cell * 0.46,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, cell * 0.05)
          ..color = color.withValues(alpha: 0.35),
      );
    }
  }

  void _drawSafeMark(Canvas canvas, Offset center, double cell, Paint fill) {
    final outer = _star(center, cell * 0.22, cell * 0.1);
    fill.color = const Color(0xFF6B6458).withValues(alpha: 0.55);
    canvas.drawPath(outer, fill);
    final inner = _star(center, cell * 0.12, cell * 0.05);
    fill.color = const Color(0xFF3D3933).withValues(alpha: 0.7);
    canvas.drawPath(inner, fill);
  }

  void _drawCenter(Canvas canvas, double cell, Paint fill, Paint stroke) {
    final left = 6 * cell;
    final top = 6 * cell;
    final right = 9 * cell;
    final bottom = 9 * cell;
    final center = Offset(7.5 * cell, 7.5 * cell);

    final triangles = <(Color, Path)>[
      (LudoColor.red.color, Path()..moveTo(left, top)..lineTo(left, bottom)..lineTo(center.dx, center.dy)..close()),
      (LudoColor.green.color, Path()..moveTo(left, top)..lineTo(right, top)..lineTo(center.dx, center.dy)..close()),
      (LudoColor.yellow.color, Path()..moveTo(right, top)..lineTo(right, bottom)..lineTo(center.dx, center.dy)..close()),
      (LudoColor.blue.color, Path()..moveTo(left, bottom)..lineTo(right, bottom)..lineTo(center.dx, center.dy)..close()),
    ];

    // Soft center well
    canvas.drawRect(
      Rect.fromLTRB(left, top, right, bottom),
      Paint()..color = const Color(0xFFEDE7DB),
    );

    final divider = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, cell * 0.07)
      ..color = Colors.white.withValues(alpha: 0.75);

    for (final item in triangles) {
      fill.color = item.$1.withValues(alpha: 0.92);
      canvas.drawPath(item.$2, fill);
      canvas.drawPath(item.$2, divider);
    }

    canvas.drawCircle(
      center,
      cell * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
  }

  Path _star(Offset center, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) => false;
}
