import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_turn_timer.dart';

/// Compact 1v1 player strip for the locked playfield.
class LudoPlayerStrip extends StatelessWidget {
  const LudoPlayerStrip({
    super.key,
    required this.participant,
    required this.myUserId,
    required this.isActive,
    this.turnEndsAt,
    this.timingEstimated = false,
    this.statusOverride,
    this.startingRoll,
    this.showYouLabel = false,
  });

  final LudoMatchParticipant participant;
  final String? myUserId;
  final bool isActive;
  final DateTime? turnEndsAt;
  final bool timingEstimated;
  final String? statusOverride;
  final int? startingRoll;
  final bool showYouLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = participant.color ?? LudoColor.red;
    final isMe = myUserId != null && participant.userId == myUserId;
    final name = isMe ? participant.fullName : participant.displayLabel(myUserId: myUserId);
    final status = statusOverride ??
        (isActive
            ? (isMe ? 'Your turn' : 'Playing')
            : (isMe ? 'Waiting' : 'Waiting'));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? color.color.withValues(alpha: scheme.brightness == Brightness.dark ? 0.16 : 0.08)
            : scheme.surface.withValues(alpha: 0.0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color.color.withValues(alpha: 0.55) : scheme.outlineVariant.withValues(alpha: 0.35),
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          _Avatar(color: isActive ? color.color : color.mutedColor, name: name, active: isActive),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (showYouLabel || isMe) ...[
                      Text(
                        'YOU',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: color.color,
                              letterSpacing: 0.4,
                            ),
                      ),
                      Text(' · ', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline)),
                    ],
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isActive ? scheme.onSurface : scheme.onSurfaceVariant,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
          if (startingRoll != null) ...[
            const SizedBox(width: 8),
            _RollChip(value: startingRoll!, color: color.color),
          ],
          if (isActive && turnEndsAt != null) ...[
            const SizedBox(width: 8),
            LudoTurnTimer(turnEndsAt: turnEndsAt, estimated: timingEstimated, compact: true),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.color, required this.name, required this.active});

  final Color color;
  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: active ? 0.95 : 0.55), width: 2),
        boxShadow: active
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      child: Text(
        initial,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
  }
}

class _RollChip extends StatelessWidget {
  const _RollChip({required this.value, required this.color});
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$value',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }
}
