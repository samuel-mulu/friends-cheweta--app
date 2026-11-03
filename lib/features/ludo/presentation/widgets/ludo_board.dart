import 'dart:async';
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_painter.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_token.dart';

class LudoBoard extends StatelessWidget {
  const LudoBoard({
    super.key,
    this.tokens = const [],
    this.animatedMove,
    this.animationSequence = 0,
  });

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
          final tokenSize = cell * 0.72;
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
                  // Static board — isolated so token/timer rebuilds skip this layer.
                  const Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: LudoBoardPainter()),
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
  const _PositionedToken({
    required this.token,
    required this.boardSize,
    required this.tokenSize,
  });

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
      stackCount: token.stackCount,
      boardSize: boardSize,
    );
    return Positioned(
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

class _MovingTokenOverlay extends StatefulWidget {
  const _MovingTokenOverlay({
    super.key,
    required this.move,
    required this.boardSize,
    required this.tokenSize,
  });

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
        child: LudoTokenPiece(
          color: token.color,
          size: widget.tokenSize,
          baseIndex: _baseIndex(token.id),
          finished: token.state == LudoTokenState.finished,
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
