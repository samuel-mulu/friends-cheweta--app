import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/match/presentation/widgets/crown_icon.dart';
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
    this.recentRolls = const [],
    this.strikes = 0,
    this.maxStrikes = 3,
    this.reaction,
    this.reactionSeq = 0,
    this.onRoll,
    this.tokensHome = 0,
    this.tokensToWin = 4,
    this.diceSettleDuration = const Duration(milliseconds: 650),
    this.onDiceSettled,
  });

  /// Length of the settle tumble (the timeline's dice scene, catch-up applied).
  final Duration diceSettleDuration;

  /// Reports that the shown roll has landed (completes the dice scene).
  final VoidCallback? onDiceSettled;

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

  /// Most recent rolls first (max 3), shown as small faces under the dice.
  final List<int> recentRolls;

  /// Consecutive turn timeouts ("away strikes"); forfeit at [maxStrikes].
  final int strikes;
  final int maxStrikes;

  /// Phrase or emoji this player just sent (shown briefly above the avatar).
  final String? reaction;
  final int reactionSeq;
  final VoidCallback? onRoll;

  /// Goal progress: crowns filled per token home, out of [tokensToWin].
  final int tokensHome;
  final int tokensToWin;

  LudoColor get color => participant.color ?? LudoColor.red;
  bool get onRight => corner == LudoCorner.topRight || corner == LudoCorner.bottomRight;
}

/// A corner seat: avatar card (name, countdown) and the player's own dice on
/// the side facing the board, with their last rolls underneath.
class LudoSeat extends StatelessWidget {
  const LudoSeat({super.key, required this.seat, this.onWarningSecond});

  final LudoSeatView seat;

  /// Called once per second during the last seconds of this seat's turn.
  final VoidCallback? onWarningSecond;

  @override
  Widget build(BuildContext context) {
    final profile = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AvatarCard(seat: seat),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 88),
          child: Text(
            seat.isMe ? 'You' : seat.participant.displayLabel(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: seat.active ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Semantics(
            label: '${seat.tokensHome} of ${seat.tokensToWin} tokens home',
            child: CrownRow(count: seat.tokensToWin, filled: seat.tokensHome, size: 11, spacing: 1),
          ),
        ),
        if (seat.strikes > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < seat.maxStrikes; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < seat.strikes ? const Color(0xFFFF6B6B) : Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(
          height: 16,
          child: seat.active && seat.turnEndsAt != null
              ? _Countdown(
                  endsAt: seat.turnEndsAt!,
                  onWarningSecond: onWarningSecond,
                )
              : seat.status == null
                  ? null
                  : Text(
                      seat.status!,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
        ),
      ],
    );

    final dice = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LudoDice(
          value: seat.diceValue,
          animateKey: seat.diceKey,
          spinning: seat.spinning,
          state: seat.diceState,
          onTap: seat.diceState == LudoDiceVisualState.ready ? seat.onRoll : null,
          accentColor: seat.color,
          size: seat.isMe ? 58 : 44,
          showRollHint: seat.isMe && seat.diceState == LudoDiceVisualState.ready,
          settleDuration: seat.diceSettleDuration,
          onSettled: seat.onDiceSettled,
        ),
        if (seat.recentRolls.isNotEmpty && !(seat.isMe && seat.diceState == LudoDiceVisualState.ready)) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final roll in seat.recentRolls.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Opacity(opacity: 0.85, child: LudoDiceFace(value: roll, size: 15, color: seat.color)),
                ),
            ],
          ),
        ],
      ],
    );

    final children = seat.onRight ? [dice, const SizedBox(width: 12), profile] : [profile, const SizedBox(width: 12), dice];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: seat.resigned ? 0.4 : 1,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({required this.seat});
  final LudoSeatView seat;

  @override
  Widget build(BuildContext context) {
    final color = seat.color;
    final size = seat.isMe ? 56.0 : 48.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: seat.active
                  ? [Color.lerp(color.color, Colors.white, 0.2)!, color.deepColor]
                  : [color.mutedColor, Color.lerp(color.mutedColor, Colors.black, 0.3)!],
            ),
            border: Border.all(color: seat.active ? Colors.white : Colors.white.withValues(alpha: 0.35), width: seat.active ? 2.5 : 1.5),
            boxShadow: [
              if (seat.active) BoxShadow(color: color.color.withValues(alpha: 0.8), blurRadius: 18, spreadRadius: 2),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(seat.participant.fullName),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.36),
          ),
        ),
        if (seat.reaction != null)
          Positioned(
            bottom: size - 4,
            left: -20,
            right: -20,
            child: Center(child: _ReactionBubble(key: ValueKey(seat.reactionSeq), text: seat.reaction!)),
          ),
        if (seat.rank != null)
          Positioned(
            right: -6,
            top: -6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: const Color(0xFFFFC83D), borderRadius: BorderRadius.circular(10)),
              child: Text(
                seat.rank == 1 ? '1st' : '#${seat.rank}',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFF3B2A00)),
              ),
            ),
          ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }
}

/// Pops in above the avatar (emoji large, phrases as a small speech bubble).
class _ReactionBubble extends StatelessWidget {
  const _ReactionBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final emoji = text.runes.length <= 2 && !RegExp(r'[A-Za-z]').hasMatch(text);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: emoji ? 6 : 10, vertical: emoji ? 2 : 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            fontSize: emoji ? 22 : 12,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF16202E),
          ),
        ),
      ),
    );
  }
}

/// Seconds left in the active turn, from the server deadline.
class _Countdown extends ConsumerStatefulWidget {
  const _Countdown({required this.endsAt, this.onWarningSecond});
  final DateTime endsAt;
  final VoidCallback? onWarningSecond;

  @override
  ConsumerState<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends ConsumerState<_Countdown> {
  static const _warnFrom = 5;
  Timer? _ticker;
  int _seconds = 0;
  int? _lastWarned;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      _lastWarned = null;
      _tick();
    }
  }

  void _tick() {
    if (!mounted) return;
    final remaining = widget.endsAt.difference(ref.read(gameSocketServiceProvider).serverNow());
    final seconds = remaining.isNegative ? 0 : (remaining.inMilliseconds / 1000).ceil();
    if (seconds > 0 && seconds <= _warnFrom && seconds != _lastWarned) {
      _lastWarned = seconds;
      widget.onWarningSecond?.call();
    }
    if (seconds != _seconds) setState(() => _seconds = seconds);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _seconds <= _warnFrom;
    final color = urgent ? const Color(0xFFFF6B6B) : const Color(0xFFFFD54F);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: 13, color: color),
        const SizedBox(width: 3),
        Text('${_seconds}s', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
      ],
    );
  }
}

/// Two seats side by side (top or bottom of the board).
class LudoSeatRow extends StatelessWidget {
  const LudoSeatRow({super.key, this.left, this.right, this.onWarningSecond, this.warnUserId});
  final LudoSeatView? left;
  final LudoSeatView? right;
  final VoidCallback? onWarningSecond;
  final String? warnUserId;

  @override
  Widget build(BuildContext context) {
    // Each seat owns half the row and scales down on narrow phones instead of
    // overflowing (4 players on a 360px screen).
    Widget seat(LudoSeatView? view, Alignment alignment) => Expanded(
          child: Align(
            alignment: alignment,
            child: view == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: alignment,
                    child: LudoSeat(seat: view, onWarningSecond: view.participant.userId == warnUserId ? onWarningSecond : null),
                  ),
          ),
        );
    return SizedBox(
      height: 108,
      child: Row(children: [seat(left, Alignment.centerLeft), const SizedBox(width: 8), seat(right, Alignment.centerRight)]),
    );
  }
}
