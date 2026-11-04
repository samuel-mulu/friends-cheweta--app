import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_painter.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_token.dart';

/// The playfield. Renders server state only; [animatedMove] is the move the
/// presentation queue is currently showing (walked cell by cell).
class LudoBoard extends StatelessWidget {
  const LudoBoard({
    super.key,
    this.tokens = const [],
    this.animatedMove,
    this.animationSequence = 0,
    this.orientation = LudoBoardOrientation.identity,
    this.onStep,
  });

  final List<LudoBoardTokenView> tokens;
  final LudoMoveResolution? animatedMove;
  final int animationSequence;
  final LudoBoardOrientation orientation;

  /// Called each time the walking token lands on a cell (for step sounds).
  final VoidCallback? onStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final cell = size / LudoBoardGeometry.gridSize;
          final tokenSize = cell * 0.72;
          final move = animatedMove;

          Offset centerOf(LudoColor color, int progress, int baseIndex, {int stackIndex = 0, int stackCount = 1}) =>
              orientation.rotate(
                LudoBoardGeometry.tokenCenter(
                  color: color,
                  progress: progress,
                  baseIndex: baseIndex,
                  stackIndex: stackIndex,
                  stackCount: stackCount,
                  boardSize: size,
                ),
                size,
              );

          // While the attacker walks, captured tokens wait on the target cell;
          // they fly home when the capture is presented.
          final holdAt = move == null || move.capturedTokenIds.isEmpty
              ? null
              : centerOf(move.tokenAfter.color, move.tokenAfter.progress, 0);

          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.35 : 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Static board, isolated so token/timer rebuilds skip this layer.
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: RotatedBox(
                        quarterTurns: orientation.quarterTurns,
                        child: const CustomPaint(painter: LudoBoardPainter()),
                      ),
                    ),
                  ),
                  for (final token in tokens)
                    if (move?.tokenAfter.id != token.id)
                      _PlacedToken(
                        // Keys keep each token's element (and its implicit
                        // animation) attached to the right token.
                        key: ValueKey(token.id),
                        token: token,
                        center: holdAt != null && move!.capturedTokenIds.contains(token.id)
                            ? holdAt
                            : centerOf(token.color, token.progress, token.baseIndex,
                                stackIndex: token.stackIndex, stackCount: token.stackCount),
                        tokenSize: tokenSize,
                      ),
                  if (move != null)
                    _WalkingToken(
                      key: ValueKey('move-$animationSequence'),
                      move: move,
                      cells: [
                        for (final progress in LudoMotion.path(move))
                          centerOf(move.tokenAfter.color, progress, _baseIndex(move.tokenAfter.id)),
                      ],
                      tokenSize: tokenSize,
                      lift: cell * 0.38,
                      onStep: onStep,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static int _baseIndex(String tokenId) {
    final value = int.tryParse(tokenId.split('-').last) ?? 1;
    return (value - 1).clamp(0, 3).toInt();
  }
}

class _PlacedToken extends StatelessWidget {
  const _PlacedToken({super.key, required this.token, required this.center, required this.tokenSize});

  final LudoBoardTokenView token;
  final Offset center;
  final double tokenSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      // Implicit motion for jumps that are not walked: capture flights home,
      // stack re-arrangement and recovery snaps.
      duration: LudoMotion.captureFlight,
      curve: Curves.easeInOutCubic,
      left: center.dx - tokenSize / 2,
      top: center.dy - tokenSize / 2,
      width: tokenSize,
      height: tokenSize,
      child: LudoTokenPiece(
        color: token.color,
        size: tokenSize,
        baseIndex: token.baseIndex,
        highlighted: token.highlighted,
        emphasized: token.emphasized,
        pending: token.pending,
        finished: token.finished,
        onTap: token.onTap,
      ),
    );
  }
}

/// Walks a token along [cells], hopping once per cell.
class _WalkingToken extends StatefulWidget {
  const _WalkingToken({
    super.key,
    required this.move,
    required this.cells,
    required this.tokenSize,
    required this.lift,
    this.onStep,
  });

  final LudoMoveResolution move;
  final List<Offset> cells;
  final double tokenSize;
  final double lift;
  final VoidCallback? onStep;

  @override
  State<_WalkingToken> createState() => _WalkingTokenState();
}

class _WalkingTokenState extends State<_WalkingToken> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _landed = 0;

  int get _hops => widget.cells.length - 1;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: LudoMotion.stepDuration * math.max(_hops, 1))
      ..addListener(_reportLandings)
      ..forward();
  }

  void _reportLandings() {
    final landed = (_controller.value * _hops).floor();
    while (_landed < landed) {
      _landed++;
      widget.onStep?.call();
    }
    if (_controller.isCompleted && _landed < _hops) {
      _landed = _hops;
      widget.onStep?.call();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.move.tokenAfter;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final cells = widget.cells;
        final t = _controller.value * _hops;
        final index = t.floor().clamp(0, math.max(_hops - 1, 0)).toInt();
        final f = _hops == 0 ? 1.0 : (t - index).clamp(0.0, 1.0);
        final from = cells[index];
        final to = cells[math.min(index + 1, cells.length - 1)];
        final arc = math.sin(math.pi * f);
        final center = Offset.lerp(from, to, Curves.easeInOut.transform(f))! - Offset(0, widget.lift * arc);
        return Positioned(
          left: center.dx - widget.tokenSize / 2,
          top: center.dy - widget.tokenSize / 2,
          width: widget.tokenSize,
          height: widget.tokenSize,
          child: Transform.scale(scale: 1 + 0.14 * arc, child: child),
        );
      },
      child: IgnorePointer(
        child: LudoTokenPiece(
          color: token.color,
          size: widget.tokenSize,
          baseIndex: LudoBoard._baseIndex(token.id),
          finished: token.state == LudoTokenState.finished,
        ),
      ),
    );
  }
}
