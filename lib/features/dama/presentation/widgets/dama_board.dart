import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/dama/application/dama_selection.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_paint.dart';
import 'package:friends_game_app/features/match/presentation/widgets/celebration.dart';

/// The Dama board. Draws the server's board; when a new move arrives the piece
/// travels its path hop by hop and each captured piece fades as it is jumped.
/// Taps are reported as squares; the picker decides what they mean.
class DamaBoard extends StatefulWidget {
  const DamaBoard({
    super.key,
    required this.board,
    required this.version,
    required this.flipped,
    this.lastMove,
    this.lastMovePromoted = false,
    this.selection = DamaSelection.none,
    this.targets = const {},
    this.movable = const {},
    this.mustCapture = false,
    this.onTapSquare,
    this.onHop,
    this.hopMs = 230,
  });

  final String board;
  final int version;
  final bool flipped;
  final DamaMove? lastMove;
  final bool lastMovePromoted;
  final DamaSelection selection;
  final Set<int> targets;
  final Set<int> movable;

  /// Movable pieces pulse when the player must capture.
  final bool mustCapture;
  final ValueChanged<int>? onTapSquare;

  /// Each landing during a move animation (true when that hop captured).
  final void Function(bool capture)? onHop;
  final int hopMs;

  @override
  State<DamaBoard> createState() => _DamaBoardState();
}

class _DamaBoardState extends State<DamaBoard> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  /// Board before the animating move (pieces are drawn from it until it ends).
  String? _fromBoard;
  DamaMove? _animating;
  int _lastHop = 0;
  int? _crownBurstSquare;
  int _crownBurstSeq = 0;

  @override
  void initState() {
    super.initState();
    _move.addListener(_onTick);
    _move.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finishMove();
    });
    _syncPulse();
  }

  @override
  void didUpdateWidget(DamaBoard old) {
    super.didUpdateWidget(old);
    final move = widget.lastMove;
    if (widget.version > old.version && move != null && move != old.lastMove && old.board != widget.board) {
      // A move arriving mid-animation starts from the board after the previous one.
      _fromBoard = old.board;
      _animating = move;
      _lastHop = 0;
      _move
        ..duration = Duration(milliseconds: widget.hopMs * (move.path.length - 1))
        ..forward(from: 0);
    }
    if (old.mustCapture != widget.mustCapture) _syncPulse();
  }

  void _syncPulse() {
    if (widget.mustCapture) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  void _onTick() {
    final move = _animating;
    if (move == null) return;
    final hops = move.path.length - 1;
    final reached = (_move.value * hops).floor().clamp(0, hops);
    while (_lastHop < reached) {
      _lastHop++;
      widget.onHop?.call(move.isCapture); // in a capture every hop takes a piece
    }
  }

  void _finishMove() {
    final move = _animating;
    setState(() {
      if (move != null && widget.lastMovePromoted && widget.lastMove == move) {
        _crownBurstSquare = move.to;
        _crownBurstSeq++;
      }
      _animating = null;
      _fromBoard = null;
    });
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(constraints.maxWidth, constraints.maxHeight);
          final geometry = DamaBoardGeometry(size: size, flipped: widget.flipped);
          return SizedBox.square(
            dimension: size,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final square = geometry.squareAt(details.localPosition);
                    if (square != null) widget.onTapSquare?.call(square);
                  },
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.square(size),
                      painter: _DamaBoardPainter(
                        geometry: geometry,
                        board: _fromBoard ?? widget.board,
                        animating: _animating,
                        progress: _move,
                        pulse: _pulse,
                        selection: widget.selection,
                        targets: widget.targets,
                        movable: widget.movable,
                        mustCapture: widget.mustCapture,
                        lastMove: _animating == null ? widget.lastMove : null,
                      ),
                    ),
                  ),
                ),
                if (_crownBurstSquare case final square?)
                  Positioned.fromRect(
                    rect: Rect.fromCenter(center: geometry.center(square), width: geometry.cell * 4, height: geometry.cell * 4),
                    child: Confetti(key: ValueKey('crown-$_crownBurstSeq'), seed: _crownBurstSeq, count: 24),
                  ),
              ],
            ),
          );
        },
      );
}

class _DamaBoardPainter extends CustomPainter {
  _DamaBoardPainter({
    required this.geometry,
    required this.board,
    required this.animating,
    required this.progress,
    required this.pulse,
    required this.selection,
    required this.targets,
    required this.movable,
    required this.mustCapture,
    required this.lastMove,
  }) : super(repaint: Listenable.merge([progress, pulse]));

  final DamaBoardGeometry geometry;
  final String board;
  final DamaMove? animating;
  final Animation<double> progress;
  final Animation<double> pulse;
  final DamaSelection selection;
  final Set<int> targets;
  final Set<int> movable;
  final bool mustCapture;
  final DamaMove? lastMove;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    paintDamaBoard(canvas, g);
    final radius = g.cell * 0.4;

    if (lastMove case final move?) {
      final tint = Paint()..color = DamaPalette.lastMove;
      for (final square in move.path) {
        canvas.drawRect(g.squareRect(square).deflate(g.cell * 0.04), tint);
      }
    }

    // Pieces that may move: a soft ring (pulsing when a capture is compulsory).
    for (final square in movable) {
      final strength = mustCapture ? 0.45 + 0.55 * pulse.value : 0.5;
      canvas.drawCircle(
        g.center(square),
        radius * (1.12 + (mustCapture ? 0.08 * pulse.value : 0)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.cell * 0.06
          ..color = (mustCapture ? DamaPalette.mustCapture : DamaPalette.goldLight).withValues(alpha: strength),
      );
    }

    final moving = animating;
    final hops = moving == null ? 0 : moving.path.length - 1;
    final t = moving == null ? 0.0 : progress.value * hops;

    for (var square = 0; square < 64; square++) {
      final piece = DamaPiece.fromCell(board[square]);
      if (piece == null || (moving != null && square == moving.from)) continue;
      var opacity = 1.0;
      if (moving != null) {
        final index = moving.captured.indexOf(square);
        // The i-th captured piece fades during hop i+1 (it stays until jumped).
        if (index >= 0) opacity = (1 - (t - index).clamp(0.0, 1.0)).toDouble();
      }
      paintDamaPiece(canvas, g.center(square), radius, piece, opacity: opacity);
    }

    if (selection.from case final from?) {
      canvas.drawCircle(
        g.center(from),
        radius * 1.16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.cell * 0.08
          ..color = DamaPalette.target,
      );
      for (final step in selection.steps) {
        canvas.drawCircle(g.center(step), radius * 0.3, Paint()..color = DamaPalette.target.withValues(alpha: 0.8));
      }
    }
    for (final square in targets) {
      final c = g.center(square);
      canvas.drawCircle(c, radius * 0.42, Paint()..color = DamaPalette.target.withValues(alpha: 0.35));
      canvas.drawCircle(c, radius * 0.22, Paint()..color = DamaPalette.target);
    }

    if (moving != null) {
      final piece = DamaPiece.fromCell(board[moving.from]);
      if (piece != null) {
        final hop = t.floor().clamp(0, hops - 1);
        final local = Curves.easeInOut.transform((t - hop).clamp(0.0, 1.0).toDouble());
        final a = g.center(moving.path[hop]);
        final b = g.center(moving.path[hop + 1]);
        // A small arc while the piece is lifted off the board.
        final lift = math.sin(local * math.pi);
        final position = Offset.lerp(a, b, local)! - Offset(0, g.cell * 0.18 * lift);
        paintDamaPiece(canvas, position, radius * (1 + 0.08 * lift), piece, lift: lift);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DamaBoardPainter old) =>
      old.board != board ||
      old.animating != animating ||
      old.selection != selection ||
      old.targets != targets ||
      old.movable != movable ||
      old.mustCapture != mustCapture ||
      old.lastMove != lastMove ||
      old.geometry.size != geometry.size ||
      old.geometry.flipped != geometry.flipped;
}
