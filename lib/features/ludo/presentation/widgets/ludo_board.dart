import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/celebration.dart';
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
    this.ghosts = const [],
    this.onBoardTap,
    this.homeBurst,
  });

  final List<LudoBoardTokenView> tokens;
  final LudoMoveResolution? animatedMove;
  final int animationSequence;
  final LudoBoardOrientation orientation;

  /// Landing previews for the player's legal moves.
  final List<LudoGhostView> ghosts;

  /// Called each time the walking token lands on a cell (for step sounds).
  final VoidCallback? onStep;

  /// A tap that hit no movable token or preview (so the screen can explain why).
  final VoidCallback? onBoardTap;

  /// Confetti at this color's home triangle; a new [seq] plays it again.
  final ({LudoColor color, int seq})? homeBurst;

  /// Smallest comfortable touch target for a movable token.
  static const minHit = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final cell = size / LudoBoardGeometry.gridSize;
          final tokenSize = cell * 0.95;
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

          Widget placed(LudoBoardTokenView token) => _PlacedToken(
                // Keys keep each token's element (and its implicit animation)
                // attached to the right token, even when paint order changes.
                key: ValueKey(token.id),
                token: token,
                center: holdAt != null && move!.capturedTokenIds.contains(token.id)
                    ? holdAt
                    : centerOf(token.color, token.progress, token.baseIndex,
                        stackIndex: token.stackIndex, stackCount: token.stackCount),
                tokenSize: tokenSize,
              );

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
            // Only the painted board is clipped; pin heads on the edge rows may
            // rise above it.
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Static board, isolated so token/timer rebuilds skip this layer.
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: RepaintBoundary(
                      child: RotatedBox(
                        quarterTurns: orientation.quarterTurns,
                        child: const CustomPaint(painter: LudoBoardPainter()),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onBoardTap),
                ),
                // Paint order = touch priority: idle tokens, then previews, then
                // movable tokens on top, so the glowing token always gets the tap.
                for (final token in tokens)
                  if (!token.isSelectable && move?.tokenAfter.id != token.id) placed(token),
                for (final ghost in ghosts)
                  _Ghost(
                    key: ValueKey('ghost-${ghost.tokenId}'),
                    ghost: ghost,
                    center: centerOf(ghost.color, ghost.toProgress, 0),
                    tokenSize: tokenSize,
                  ),
                for (final token in tokens)
                  if (token.isSelectable && move?.tokenAfter.id != token.id) placed(token),
                if (homeBurst case final burst?)
                  Positioned.fromRect(
                    rect: Rect.fromCenter(
                      center: centerOf(burst.color, LudoBoard.finishProgress, 0),
                      width: cell * 6,
                      height: cell * 6,
                    ),
                    child: Confetti(key: ValueKey('home-burst-${burst.seq}'), seed: burst.seq, count: 28),
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
          );
        },
      ),
    );
  }

  /// Progress of a token that reached home (centre triangle).
  static const finishProgress = 57;

  /// Tokens are pins: place them so the tip (not the middle) sits on the cell.
  static const pinAnchor = 0.72;

  static int _baseIndex(String tokenId) {
    final value = int.tryParse(tokenId.split('-').last) ?? 1;
    return (value - 1).clamp(0, 3).toInt();
  }
}

/// Faint pin where a legal token would land, with a ⚔ (capture) or ★ (safe)
/// badge. Tapping it moves that token, like tapping the token itself.
class _Ghost extends StatelessWidget {
  const _Ghost({super.key, required this.ghost, required this.center, required this.tokenSize});
  final LudoGhostView ghost;
  final Offset center;
  final double tokenSize;

  @override
  Widget build(BuildContext context) {
    final badge = ghost.captures ? '⚔' : (ghost.safe ? '★' : null);
    return Positioned(
      left: center.dx - tokenSize / 2,
      top: center.dy - tokenSize * LudoBoard.pinAnchor,
      width: tokenSize,
      height: tokenSize,
      child: Semantics(
        button: ghost.onTap != null,
        label: 'Move ${ghost.tokenId} here${ghost.captures ? ', captures' : ''}${ghost.safe ? ', safe square' : ''}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: ghost.onTap,
          // The visuals are decorative; the label above says what tapping does.
          child: ExcludeSemantics(
              child: Stack(
            clipBehavior: Clip.none,
            children: [
              Opacity(
                opacity: 0.42,
                child: IgnorePointer(child: LudoTokenPiece(color: ghost.color, size: tokenSize, baseIndex: 0)),
              ),
              if (badge != null)
                Positioned(
                  right: -tokenSize * 0.1,
                  top: -tokenSize * 0.05,
                  child: Container(
                    padding: EdgeInsets.all(tokenSize * 0.05),
                    decoration: BoxDecoration(
                      color: ghost.captures ? const Color(0xFFE53935) : const Color(0xFFFFC83D),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: Text(badge, style: TextStyle(fontSize: tokenSize * 0.28, color: Colors.white, height: 1)),
                  ),
                ),
            ],
          )),
        ),
      ),
    );
  }
}

class _PlacedToken extends StatelessWidget {
  const _PlacedToken({super.key, required this.token, required this.center, required this.tokenSize});

  final LudoBoardTokenView token;
  final Offset center;
  final double tokenSize;

  @override
  Widget build(BuildContext context) {
    // Movable tokens get a bigger box (touch target) around the same pin.
    final box = token.isSelectable ? math.max(tokenSize, LudoBoard.minHit) : tokenSize;
    final grow = (box - tokenSize) / 2;
    return AnimatedPositioned(
      // Implicit motion for jumps that are not walked: capture flights home,
      // stack re-arrangement and recovery snaps.
      duration: LudoMotion.captureFlight,
      curve: Curves.easeInOutCubic,
      left: center.dx - tokenSize / 2 - grow,
      top: center.dy - tokenSize * LudoBoard.pinAnchor - grow,
      width: box,
      height: box,
      child: LudoTokenPiece(
        hitSize: box,
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
          top: center.dy - widget.tokenSize * LudoBoard.pinAnchor,
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
