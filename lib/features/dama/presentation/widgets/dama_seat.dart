import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_paint.dart';

/// One player's bar: piece colour, name, pieces taken, the move clock (a ring
/// that empties while it is their move), away strikes and a live reaction.
class DamaSeat extends StatelessWidget {
  const DamaSeat({
    super.key,
    required this.name,
    required this.color,
    required this.isMe,
    required this.active,
    required this.captured,
    this.turnEndsAt,
    this.turnSeconds = 40,
    this.strikes = 0,
    this.maxStrikes = 3,
    this.reaction,
    this.reactionSeq = 0,
    this.onWarningSecond,
  });

  final String name;
  final DamaColor color;
  final bool isMe;
  final bool active;
  final int captured;
  final DateTime? turnEndsAt;
  final int turnSeconds;
  final int strikes;
  final int maxStrikes;
  final String? reaction;
  final int reactionSeq;

  /// Called once per second during the last seconds of this player's clock.
  final VoidCallback? onWarningSecond;

  @override
  Widget build(BuildContext context) {
    final label = isMe ? 'You' : name;
    return Semantics(
      label: '$label, ${color.label}, $captured taken${active ? ', to move' : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: active ? 0.35 : 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? DamaPalette.goldLight : Colors.white.withValues(alpha: 0.08), width: active ? 1.6 : 1),
        ),
        child: Row(children: [
          SizedBox.square(
            dimension: 46,
            child: Stack(alignment: Alignment.center, children: [
              if (active && turnEndsAt != null) _ClockRing(endsAt: turnEndsAt!, seconds: turnSeconds, onWarningSecond: onWarningSecond),
              CustomPaint(size: const Size.square(34), painter: _PieceIcon(color)),
              if (reaction != null)
                Positioned(
                  top: -2,
                  child: _ReactionBubble(key: ValueKey(reactionSeq), text: reaction!),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: active ? FontWeight.w800 : FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Row(children: [
                Text(color.label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                if (strikes > 0) ...[
                  const SizedBox(width: 8),
                  for (var i = 0; i < maxStrikes; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.circle, size: 7, color: i < strikes ? const Color(0xFFFF7A45) : Colors.white24),
                    ),
                ],
              ]),
            ]),
          ),
          _Taken(count: captured, opponent: color.opponent),
        ]),
      ),
    );
  }
}

/// Pieces taken from the opponent: a small stack and the number.
class _Taken extends StatelessWidget {
  const _Taken({required this.count, required this.opponent});
  final int count;
  final DamaColor opponent;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(size: const Size.square(20), painter: _PieceIcon(opponent)),
        const SizedBox(width: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Text(
            '×$count',
            key: ValueKey(count),
            style: const TextStyle(color: DamaPalette.goldLight, fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ]);
}

class _PieceIcon extends CustomPainter {
  const _PieceIcon(this.color);
  final DamaColor color;
  @override
  void paint(Canvas canvas, Size size) =>
      paintDamaPiece(canvas, size.center(Offset.zero) - Offset(0, size.height * 0.04), size.shortestSide * 0.42, DamaPiece(color));
  @override
  bool shouldRepaint(covariant _PieceIcon old) => old.color != color;
}

class _ClockRing extends StatefulWidget {
  const _ClockRing({required this.endsAt, required this.seconds, this.onWarningSecond});
  final DateTime endsAt;
  final int seconds;
  final VoidCallback? onWarningSecond;
  @override
  State<_ClockRing> createState() => _ClockRingState();
}

class _ClockRingState extends State<_ClockRing> {
  Timer? _timer;
  int _lastWarned = -1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final left = widget.endsAt.difference(DateTime.now()).inMilliseconds;
      final second = (left / 1000).ceil();
      if (second <= 5 && second > 0 && second != _lastWarned) {
        _lastWarned = second;
        widget.onWarningSecond?.call();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(DateTime.now()).inMilliseconds / 1000;
    final fraction = (left / math.max(widget.seconds, 1)).clamp(0.0, 1.0).toDouble();
    return CustomPaint(size: const Size.square(46), painter: _RingPainter(fraction));
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white12);
    final color = fraction > 0.33 ? DamaPalette.goldLight : const Color(0xFFFF7A45);
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.fraction != fraction;
}

class _ReactionBubble extends StatelessWidget {
  const _ReactionBubble({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.4, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.elasticOut,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
        ),
      );
}
