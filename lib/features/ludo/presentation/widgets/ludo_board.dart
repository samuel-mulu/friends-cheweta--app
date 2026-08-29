import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';

class LudoBoard extends StatelessWidget {
  const LudoBoard({super.key, this.tokens = const [], this.animatedMove, this.animationSequence = 0});

  final List<LudoBoardTokenView> tokens;
  final LudoMoveResolution? animatedMove;
  final int animationSequence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final cell = size / LudoBoardGeometry.gridSize;
          final tokenSize = cell * .72;
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? .24 : .09),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LudoBoardPainter(
                        surface: theme.colorScheme.surface,
                        line: theme.colorScheme.outline.withValues(alpha: .35),
                      ),
                    ),
                  ),
                  for (final token in tokens)
                    if (animatedMove?.tokenAfter.id != token.id)
                      _PositionedToken(
                        token: token,
                        boardSize: size,
                        tokenSize: tokenSize,
                      ),
                  if (animatedMove != null)
                    _MovingTokenOverlay(
                      key: ValueKey('move-$animationSequence'),
                      move: animatedMove!,
                      boardSize: size,
                      tokenSize: tokenSize,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PositionedToken extends StatelessWidget {
  const _PositionedToken({required this.token, required this.boardSize, required this.tokenSize});

  final LudoBoardTokenView token;
  final double boardSize;
  final double tokenSize;

  @override
  Widget build(BuildContext context) {
    final center = LudoBoardGeometry.tokenCenter(
      color: token.color,
      progress: token.progress,
      baseIndex: token.baseIndex,
      stackIndex: token.stackIndex,
      boardSize: boardSize,
    );
    return Positioned(
      left: center.dx - tokenSize / 2,
      top: center.dy - tokenSize / 2,
      width: tokenSize,
      height: tokenSize,
      child: Semantics(
        button: token.onTap != null,
        label: '${token.color.name} token ${token.baseIndex + 1}${token.highlighted ? ', available move' : ''}',
        child: GestureDetector(
          onTap: token.onTap,
          child: AnimatedScale(
            scale: token.emphasized ? 1.22 : token.highlighted ? 1.12 : 1,
            duration: const Duration(milliseconds: 180),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: token.color.color,
                border: Border.all(color: Colors.white, width: token.highlighted ? 2.4 : 1.5),
                boxShadow: [
                  BoxShadow(
                    color: token.color.color.withValues(alpha: token.highlighted ? .48 : .24),
                    blurRadius: token.emphasized ? 14 : token.highlighted ? 9 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: tokenSize * .3,
                  height: tokenSize * .3,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



class _MovingTokenOverlay extends StatefulWidget {
  const _MovingTokenOverlay({super.key, required this.move, required this.boardSize, required this.tokenSize});
  final LudoMoveResolution move;
  final double boardSize;
  final double tokenSize;

  @override
  State<_MovingTokenOverlay> createState() => _MovingTokenOverlayState();
}

class _MovingTokenOverlayState extends State<_MovingTokenOverlay> {
  late int _progress;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _progress = widget.move.tokenBefore.progress;
    _start();
  }

  void _start() {
    final target = widget.move.tokenAfter.progress;
    if (_progress == target) return;
    _timer = Timer.periodic(const Duration(milliseconds: 105), (timer) {
      if (!mounted) return;
      if (_progress < 0) {
        setState(() => _progress = 0);
      } else if (_progress < target) {
        setState(() => _progress += 1);
      }
      if (_progress >= target) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.move.tokenAfter;
    final center = LudoBoardGeometry.tokenCenter(
      color: token.color,
      progress: _progress,
      baseIndex: _baseIndex(token.id),
      boardSize: widget.boardSize,
    );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 95),
      curve: Curves.easeOut,
      left: center.dx - widget.tokenSize / 2,
      top: center.dy - widget.tokenSize / 2,
      width: widget.tokenSize,
      height: widget.tokenSize,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: token.color.color,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: token.color.color.withValues(alpha: .45), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Center(
            child: Container(
              width: widget.tokenSize * .3,
              height: widget.tokenSize * .3,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }

  int _baseIndex(String tokenId) {
    final part = tokenId.split('-').last;
    final value = int.tryParse(part) ?? 1;
    return (value - 1).clamp(0, 3).toInt();
  }
}

class _LudoBoardPainter extends CustomPainter {
  _LudoBoardPainter({required this.surface, required this.line});

  final Color surface;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / LudoBoardGeometry.gridSize;
    final paint = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75
      ..color = line;

    canvas.drawRect(Offset.zero & size, Paint()..color = surface);

    _drawBase(canvas, cell, const Rect.fromLTWH(0, 0, 6, 6), LudoColor.red.color, paint, stroke);
    _drawBase(canvas, cell, const Rect.fromLTWH(9, 0, 6, 6), LudoColor.green.color, paint, stroke);
    _drawBase(canvas, cell, const Rect.fromLTWH(9, 9, 6, 6), LudoColor.yellow.color, paint, stroke);
    _drawBase(canvas, cell, const Rect.fromLTWH(0, 9, 6, 6), LudoColor.blue.color, paint, stroke);

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
        paint.color = homeColors[key]?.withValues(alpha: .82) ?? surface;
        canvas.drawRect(rect, paint);
        canvas.drawRect(rect, stroke);
      }
    }

    for (final color in LudoColor.values) {
      final start = LudoBoardGeometry.track[color.startIndex];
      final rect = Rect.fromLTWH(start.column * cell, start.row * cell, cell, cell);
      paint.color = color.color.withValues(alpha: .86);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, stroke);
    }

    for (final index in LudoBoardGeometry.safeGlobalSquares) {
      final grid = LudoBoardGeometry.track[index];
      final center = Offset((grid.column + .5) * cell, (grid.row + .5) * cell);
      final path = _star(center, cell * .2, cell * .09);
      paint.color = index % 13 == 0
          ? _colorForStartIndex(index).color.withValues(alpha: .95)
          : line.withValues(alpha: .72);
      canvas.drawPath(path, paint);
    }

    _drawCenter(canvas, cell, paint, stroke);
    canvas.drawRect(Offset.zero & size, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = line);
  }

  void _drawBase(
    Canvas canvas,
    double cell,
    Rect gridRect,
    Color color,
    Paint paint,
    Paint stroke,
  ) {
    final rect = Rect.fromLTWH(gridRect.left * cell, gridRect.top * cell, gridRect.width * cell, gridRect.height * cell);
    paint.color = color.withValues(alpha: .92);
    canvas.drawRect(rect, paint);

    final inner = Rect.fromLTWH(
      (gridRect.left + 1) * cell,
      (gridRect.top + 1) * cell,
      4 * cell,
      4 * cell,
    );
    paint.color = surface;
    canvas.drawRRect(RRect.fromRectAndRadius(inner, Radius.circular(cell * .5)), paint);
    canvas.drawRRect(RRect.fromRectAndRadius(inner, Radius.circular(cell * .5)), stroke);

    const localCenters = <Offset>[Offset(1.8, 1.8), Offset(4.2, 1.8), Offset(1.8, 4.2), Offset(4.2, 4.2)];
    for (final point in localCenters) {
      final center = Offset((gridRect.left + point.dx) * cell, (gridRect.top + point.dy) * cell);
      paint.color = color.withValues(alpha: .18);
      canvas.drawCircle(center, cell * .48, paint);
      canvas.drawCircle(center, cell * .48, stroke);
    }
  }

  void _drawCenter(Canvas canvas, double cell, Paint paint, Paint stroke) {
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
    for (final item in triangles) {
      paint.color = item.$1.withValues(alpha: .9);
      canvas.drawPath(item.$2, paint);
      canvas.drawPath(item.$2, stroke);
    }
  }

  Path _star(Offset center, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -1.57079632679 + i * 0.62831853071;
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

  LudoColor _colorForStartIndex(int index) => switch (index) {
        0 => LudoColor.red,
        13 => LudoColor.green,
        26 => LudoColor.yellow,
        39 => LudoColor.blue,
        _ => LudoColor.red,
      };

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) {
    return oldDelegate.surface != surface || oldDelegate.line != line;
  }
}
