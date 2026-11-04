import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_dice.dart';

/// Everything one corner seat shows. Built by the match screen from server state.
class LudoSeatView {
  const LudoSeatView({
    required this.participant,
    required this.corner,
    required this.isMe,
    required this.active,
    required this.diceValue,
    required this.diceKey,
    required this.diceState,
    this.spinning = false,
    this.turnEndsAt,
    this.turnSeconds = 30,
    this.status,
    this.rank,
    this.resigned = false,
    this.onRoll,
  });

  final LudoMatchParticipant participant;
  final LudoCorner corner;
  final bool isMe;
  final bool active;
  final int? diceValue;
  final int diceKey;
  final LudoDiceVisualState diceState;
  final bool spinning;
  final DateTime? turnEndsAt;
  final int turnSeconds;
  final String? status;

  /// Finishing position once this player has finished (1 = winner).
  final int? rank;
  final bool resigned;
  final VoidCallback? onRoll;

  LudoColor get color => participant.color ?? LudoColor.red;
  bool get onRight => corner == LudoCorner.topRight || corner == LudoCorner.bottomRight;
}

/// A corner seat: avatar with turn ring + name, and the player's own dice on
/// the side facing the board.
class LudoSeat extends StatelessWidget {
  const LudoSeat({super.key, required this.seat, this.onWarningSecond});

  final LudoSeatView seat;

  /// Called once per second during the last seconds of this seat's turn.
  final VoidCallback? onWarningSecond;

  @override
  Widget build(BuildContext context) {
    final avatar = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TurnRingAvatar(seat: seat, onWarningSecond: onWarningSecond),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 84),
          child: Text(
            seat.isMe ? 'You' : seat.participant.displayLabel(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: seat.active ? FontWeight.w800 : FontWeight.w600,
                ),
          ),
        ),
        if (seat.status != null)
          Text(
            seat.status!,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: seat.active ? seat.color.color : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
      ],
    );

    final dice = _DiceDock(seat: seat);
    final children = seat.onRight ? [dice, const SizedBox(width: 10), avatar] : [avatar, const SizedBox(width: 10), dice];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: seat.resigned ? 0.45 : 1,
      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: children),
    );
  }
}

class _DiceDock extends StatelessWidget {
  const _DiceDock({required this.seat});
  final LudoSeatView seat;

  @override
  Widget build(BuildContext context) {
    final ready = seat.diceState == LudoDiceVisualState.ready;
    // The active seat's dock lights up; idle seats stay quiet.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: seat.active ? seat.color.color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: seat.active ? seat.color.color.withValues(alpha: 0.6) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: LudoDice(
        value: seat.diceValue,
        animateKey: seat.diceKey,
        spinning: seat.spinning,
        state: seat.diceState,
        onTap: ready ? seat.onRoll : null,
        accentColor: seat.color,
        size: seat.isMe ? 60 : 46,
        showRollHint: seat.isMe && ready,
      ),
    );
  }
}

class _TurnRingAvatar extends ConsumerStatefulWidget {
  const _TurnRingAvatar({required this.seat, this.onWarningSecond});
  final LudoSeatView seat;
  final VoidCallback? onWarningSecond;

  @override
  ConsumerState<_TurnRingAvatar> createState() => _TurnRingAvatarState();
}

class _TurnRingAvatarState extends ConsumerState<_TurnRingAvatar> {
  static const _warnFrom = 5;
  Timer? _ticker;
  double _fraction = 0;
  int? _lastWarned;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _TurnRingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seat.turnEndsAt != widget.seat.turnEndsAt || oldWidget.seat.active != widget.seat.active) {
      _lastWarned = null;
      _sync();
    }
  }

  void _sync() {
    _ticker?.cancel();
    if (widget.seat.active && widget.seat.turnEndsAt != null) {
      _tick();
      _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    } else if (_fraction != 0) {
      setState(() => _fraction = 0);
    }
  }

  void _tick() {
    final endsAt = widget.seat.turnEndsAt;
    if (endsAt == null || !mounted) return;
    final remaining = endsAt.difference(ref.read(gameSocketServiceProvider).serverNow());
    final total = Duration(seconds: math.max(widget.seat.turnSeconds, 1));
    final fraction = (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final secondsLeft = (remaining.inMilliseconds / 1000).ceil();
    if (secondsLeft > 0 && secondsLeft <= _warnFrom && secondsLeft != _lastWarned) {
      _lastWarned = secondsLeft;
      widget.onWarningSecond?.call();
    }
    if ((fraction - _fraction).abs() > 0.002) setState(() => _fraction = fraction);
    if (remaining.isNegative) _ticker?.cancel();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seat = widget.seat;
    final color = seat.color.color;
    final size = seat.isMe ? 54.0 : 46.0;
    final urgent = seat.active && _fraction > 0 && _fraction < 0.2;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size + 10,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(size + 10),
              painter: _RingPainter(
                fraction: seat.active ? _fraction : 0,
                color: urgent ? Theme.of(context).colorScheme.error : color,
                track: color.withValues(alpha: seat.active ? 0.2 : 0.12),
              ),
            ),
            AnimatedScale(
              duration: const Duration(milliseconds: 220),
              scale: seat.active ? 1.0 : 0.92,
              child: CircleAvatar(
                radius: size / 2,
                backgroundColor: seat.active ? color : seat.color.mutedColor,
                child: Text(
                  _initials(seat.participant.fullName),
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.34),
                ),
              ),
            ),
            if (seat.rank != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: _Badge(text: seat.rank == 1 ? '🏆' : '#${seat.rank}', color: color),
              ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color, required this.track});
  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * 0.07;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(arcRect, 0, math.pi * 2, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke);
    if (fraction <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.fraction != fraction || old.color != color || old.track != track;
}
