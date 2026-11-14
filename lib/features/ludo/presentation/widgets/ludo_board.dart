import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_board_spec.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/match/presentation/widgets/celebration.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_painter.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_token.dart';

/// A token walking its path, one hop per square.
class LudoWalkPresentation {
  const LudoWalkPresentation({
    required this.move,
    required this.path,
    required this.sequence,
    required this.duration,
    this.onStep,
    this.onCompleted,
  });

  final LudoMoveResolution move;
  final List<int> path;

  /// Timeline sequence of the scene; keys the animation so a new scene always
  /// gets a fresh walker.
  final int sequence;
  final Duration duration;

  /// Called when the token lands on each square (1-based hop index).
  final void Function(int hop)? onStep;
  final VoidCallback? onCompleted;
}

/// Captured tokens flying from their square back to the yard.
class LudoCapturePresentation {
  const LudoCapturePresentation({
    required this.tokenIds,
    required this.sequence,
    required this.duration,
    this.onCompleted,
  });

  final List<String> tokenIds;
  final int sequence;
  final Duration duration;
  final VoidCallback? onCompleted;
}

/// The playfield. Renders the *presented* snapshot only: tokens sit where the
/// timeline says they are, the current walk is drawn by [walk], and captured
/// tokens fly home with [capture]. Nothing else on the board animates
/// position, so a token can never slide ahead of what the player is watching.
class LudoBoard extends StatelessWidget {
  const LudoBoard({
    super.key,
    this.tokens = const [],
    this.board = LudoBoardSpec.standard,
    this.walk,
    this.capture,
    this.orientation = LudoBoardOrientation.identity,
    this.ghosts = const [],
    this.onBoardTap,
    this.homeBurst,
  });

  final List<LudoBoardTokenView> tokens;
  final LudoBoardSpec board;
  final LudoWalkPresentation? walk;
  final LudoCapturePresentation? capture;
  final LudoBoardOrientation orientation;

  /// Landing previews for the player's legal moves.
  final List<LudoGhostView> ghosts;

  /// A tap that hit no movable token or preview (so the screen can explain why).
  final VoidCallback? onBoardTap;

  /// Confetti at this color's home triangle; a new [seq] plays it again.
  final ({LudoColor color, int seq})? homeBurst;

  /// Smallest comfortable touch target for a movable token.
  static const minHit = 44.0;

  /// Tokens are pins: place them so the tip (not the middle) sits on the cell.
  static const pinAnchor = 0.72;

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
          final walk = this.walk;
          final capture = this.capture;

          Offset centerOf(LudoColor color, int progress, int baseIndex, {int stackIndex = 0, int stackCount = 1}) =>
              orientation.rotate(
                LudoBoardGeometry.tokenCenter(
                  color: color,
                  progress: progress,
                  baseIndex: baseIndex,
                  board: board,
                  stackIndex: stackIndex,
                  stackCount: stackCount,
                  boardSize: size,
                ),
                size,
              );

          final hidden = <String>{
            if (walk != null) walk.move.tokenId,
            ...?capture?.tokenIds,
          };
          final byId = {for (final token in tokens) token.id: token};

          Widget placed(LudoBoardTokenView token) => _PlacedToken(
                // Keys keep each token's element attached to the right token,
                // even when paint order changes.
                key: ValueKey(token.id),
                token: token,
                center: centerOf(token.color, token.progress, token.baseIndex,
                    stackIndex: token.stackIndex, stackCount: token.stackCount),
                tokenSize: tokenSize,
              );

          List<Offset> walkCells() {
            final mover = walk!.move.tokenAfter;
            final baseIndex = byId[mover.id]?.baseIndex ?? _baseIndex(mover.id);
            final cells = [for (final progress in walk.path) centerOf(mover.color, progress, baseIndex)];
            // Land inside the stack it joins, so nothing shifts when the walk ends.
            final destinationKey = LudoBoardGeometry.occupancyKey(
              color: mover.color,
              progress: mover.progress,
              tokenId: mover.id,
              board: board,
            );
            final sharing = tokens
                .where((t) =>
                    t.id != mover.id &&
                    LudoBoardGeometry.occupancyKey(color: t.color, progress: t.progress, tokenId: t.id, board: board) ==
                        destinationKey)
                .length;
            if (sharing > 0 && mover.progress >= 0 && cells.isNotEmpty) {
              cells[cells.length - 1] = centerOf(mover.color, mover.progress, baseIndex,
                  stackIndex: sharing, stackCount: sharing + 1);
            }
            return cells;
          }

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
                  if (!token.isSelectable && !hidden.contains(token.id)) placed(token),
                for (final ghost in ghosts)
                  _Ghost(
                    key: ValueKey('ghost-${ghost.tokenId}'),
                    ghost: ghost,
                    center: centerOf(ghost.color, ghost.toProgress, 0),
                    tokenSize: tokenSize,
                  ),
                for (final token in tokens)
                  if (token.isSelectable && !hidden.contains(token.id)) placed(token),
                if (homeBurst case final burst?)
                  Positioned.fromRect(
                    rect: Rect.fromCenter(
                      center: centerOf(burst.color, board.finish, 0),
                      width: cell * 6,
                      height: cell * 6,
                    ),
                    child: Confetti(key: ValueKey('home-burst-${burst.seq}'), seed: burst.seq, count: 28),
                  ),
                if (capture != null)
                  for (final (index, id) in capture.tokenIds.indexed)
                    if (byId[id] case final victim?)
                      _CaptureFlight(
                        key: ValueKey('capture-${capture.sequence}-$id'),
                        token: victim,
                        from: centerOf(victim.color, victim.progress, victim.baseIndex,
                            stackIndex: victim.stackIndex, stackCount: victim.stackCount),
                        to: centerOf(victim.color, -1, victim.baseIndex),
                        duration: capture.duration,
                        tokenSize: tokenSize,
                        lift: cell * 0.9,
                        // One report per scene, from the last flight.
                        onCompleted: index == capture.tokenIds.length - 1 ? capture.onCompleted : null,
                      ),
                if (walk != null)
                  _WalkingToken(
                    key: ValueKey('move-${walk.sequence}'),
                    token: walk.move.tokenAfter,
                    baseIndex: byId[walk.move.tokenId]?.baseIndex ?? _baseIndex(walk.move.tokenId),
                    cells: walkCells(),
                    duration: walk.duration,
                    tokenSize: tokenSize,
                    lift: cell * 0.38,
                    onStep: walk.onStep,
                    onCompleted: walk.onCompleted,
                  ),
              ],
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
      // Positions come from the presented snapshot and change only when a
      // scene lands; this short ease covers stack re-fanning and resync snaps.
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
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

/// Walks a token along [cells], hopping once per cell, and reports when done.
class _WalkingToken extends StatefulWidget {
  const _WalkingToken({
    super.key,
    required this.token,
    required this.baseIndex,
    required this.cells,
    required this.duration,
    required this.tokenSize,
    required this.lift,
    this.onStep,
    this.onCompleted,
  });

  final LudoToken token;
  final int baseIndex;
  final List<Offset> cells;
  final Duration duration;
  final double tokenSize;
  final double lift;
  final void Function(int hop)? onStep;
  final VoidCallback? onCompleted;

  @override
  State<_WalkingToken> createState() => _WalkingTokenState();
}

class _WalkingTokenState extends State<_WalkingToken> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _landed = 0;
  bool _reported = false;

  int get _hops => math.max(widget.cells.length - 1, 0);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_reportLandings)
      ..addStatusListener(_onStatus)
      ..forward();
  }

  void _reportLandings() {
    if (_hops == 0) return;
    final landed = (_controller.value * _hops).floor();
    while (_landed < landed) {
      _landed++;
      widget.onStep?.call(_landed);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _reported) return;
    _reported = true;
    while (_landed < _hops) {
      _landed++;
      widget.onStep?.call(_landed);
    }
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_reportLandings)
      ..removeStatusListener(_onStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = widget.token;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final cells = widget.cells;
        if (cells.isEmpty) return const SizedBox.shrink();
        final hops = _hops;
        final t = _controller.value * hops;
        final index = t.floor().clamp(0, math.max(hops - 1, 0)).toInt();
        final f = hops == 0 ? 1.0 : (t - index).clamp(0.0, 1.0);
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
          baseIndex: widget.baseIndex,
          finished: token.state == LudoTokenState.finished,
        ),
      ),
    );
  }
}

/// A captured token arcs from its square back to its yard slot and shrinks a
/// little on the way, like being knocked off the board.
class _CaptureFlight extends StatefulWidget {
  const _CaptureFlight({
    super.key,
    required this.token,
    required this.from,
    required this.to,
    required this.duration,
    required this.tokenSize,
    required this.lift,
    this.onCompleted,
  });

  final LudoBoardTokenView token;
  final Offset from;
  final Offset to;
  final Duration duration;
  final double tokenSize;
  final double lift;
  final VoidCallback? onCompleted;

  @override
  State<_CaptureFlight> createState() => _CaptureFlightState();
}

class _CaptureFlightState extends State<_CaptureFlight> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_reported) {
          _reported = true;
          widget.onCompleted?.call();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInCubic.transform(_controller.value);
        final arc = math.sin(math.pi * _controller.value);
        final center = Offset.lerp(widget.from, widget.to, t)! - Offset(0, widget.lift * arc);
        return Positioned(
          left: center.dx - widget.tokenSize / 2,
          top: center.dy - widget.tokenSize * LudoBoard.pinAnchor,
          width: widget.tokenSize,
          height: widget.tokenSize,
          child: Transform.scale(scale: 1.15 - 0.25 * _controller.value, child: child),
        );
      },
      child: IgnorePointer(
        child: LudoTokenPiece(
          color: widget.token.color,
          size: widget.tokenSize,
          baseIndex: widget.token.baseIndex,
          emphasized: true,
        ),
      ),
    );
  }
}
