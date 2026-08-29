import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

class LudoPlayerIdentityBar extends StatelessWidget {
  const LudoPlayerIdentityBar({
    super.key,
    required this.participants,
    required this.snapshot,
    required this.myUserId,
    required this.currentPlayerId,
  });

  final List<LudoMatchParticipant> participants;
  final LudoRuntimeSnapshot snapshot;
  final String? myUserId;
  final String? currentPlayerId;

  @override
  Widget build(BuildContext context) {
    final cards = _orderedParticipants();
    if (cards.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _PlayerIdentityCard(
            participant: cards[i],
            myUserId: myUserId,
            isActive: currentPlayerId == cards[i].userId,
            startingRoll: snapshot.startingRoll.rolls[cards[i].userId],
            resigned: snapshot.resignedPlayerIds.contains(cards[i].userId),
          )),
        ],
      ],
    );
  }

  List<LudoMatchParticipant> _orderedParticipants() {
    final cards = participants.isNotEmpty
        ? participants
        : snapshot.game.players
            .map((player) => LudoMatchParticipant(
                  userId: player.userId,
                  fullName: 'Player',
                  seat: 0,
                  color: player.color,
                ))
            .toList(growable: false);

    if (myUserId == null || cards.length < 2) return cards;
    final mine = cards.where((p) => p.userId == myUserId).toList();
    final others = cards.where((p) => p.userId != myUserId).toList();
    if (mine.isEmpty || others.isEmpty) return cards;
    return [mine.first, others.first];
  }
}

class _PlayerIdentityCard extends StatelessWidget {
  const _PlayerIdentityCard({
    required this.participant,
    required this.myUserId,
    required this.isActive,
    required this.startingRoll,
    required this.resigned,
  });

  final LudoMatchParticipant participant;
  final String? myUserId;
  final bool isActive;
  final int? startingRoll;
  final bool resigned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = participant.color ?? LudoColor.red;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? scheme.primaryContainer.withValues(alpha: .55) : scheme.surfaceContainerHighest.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? scheme.primary : scheme.outlineVariant.withValues(alpha: .45),
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          _ColorBadge(color: color, active: isActive),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  resigned
                      ? 'Resigned'
                      : '${participant.roleLabel(myUserId: myUserId)} · ${color.name.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (startingRoll != null)
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.color.withValues(alpha: 0.55)),
              ),
              child: Text(
                '$startingRoll',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color.color,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            )
          else if (isActive)
            Icon(Icons.play_circle_fill_rounded, size: 18, color: scheme.primary),
        ],
      ),
    );
  }
}

class _ColorBadge extends StatelessWidget {
  const _ColorBadge({required this.color, required this.active});

  final LudoColor color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: active ? .95 : .65), width: 2),
        boxShadow: active
            ? [
                BoxShadow(color: color.color.withValues(alpha: .35), blurRadius: 10, spreadRadius: 1),
              ]
            : null,
      ),
      child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
    );
  }
}
