import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_dice.dart';

class LudoPlayerDicePanel extends StatelessWidget {
  const LudoPlayerDicePanel({
    super.key,
    required this.myParticipant,
    required this.opponentParticipant,
    required this.myDiceValue,
    required this.opponentDiceValue,
    required this.myAnimateKey,
    required this.opponentAnimateKey,
    required this.canRollMine,
    required this.onRollMine,
    this.busy = false,
  });

  final LudoMatchParticipant myParticipant;
  final LudoMatchParticipant opponentParticipant;
  final int? myDiceValue;
  final int? opponentDiceValue;
  final int myAnimateKey;
  final int opponentAnimateKey;
  final bool canRollMine;
  final VoidCallback onRollMine;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final myColor = myParticipant.color ?? LudoColor.red;
    final opponentColor = opponentParticipant.color ?? LudoColor.green;

    return Row(
      children: [
        Expanded(
          child: _DiceSide(
            participant: myParticipant,
            color: myColor,
            diceValue: myDiceValue,
            animateKey: myAnimateKey,
            enabled: canRollMine && !busy,
            onTap: onRollMine,
            alignEnd: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'VS',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
        Expanded(
          child: _DiceSide(
            participant: opponentParticipant,
            color: opponentColor,
            diceValue: opponentDiceValue,
            animateKey: opponentAnimateKey,
            enabled: false,
            alignEnd: true,
          ),
        ),
      ],
    );
  }
}

class _DiceSide extends StatelessWidget {
  const _DiceSide({
    required this.participant,
    required this.color,
    required this.diceValue,
    required this.animateKey,
    required this.enabled,
    required this.alignEnd,
    this.onTap,
  });

  final LudoMatchParticipant participant;
  final LudoColor color;
  final int? diceValue;
  final int animateKey;
  final bool enabled;
  final VoidCallback? onTap;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                participant.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          color.name.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color.color),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: LudoDice(
            value: diceValue,
            animateKey: animateKey,
            enabled: enabled,
            onTap: onTap,
            accentColor: color,
            label: enabled ? 'Tap to roll' : null,
            compact: true,
          ),
        ),
      ],
    );
  }
}
