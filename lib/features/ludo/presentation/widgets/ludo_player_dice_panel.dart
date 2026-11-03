import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_dice.dart';

/// Bottom dice / start-roll action cluster for the locked playfield.
class LudoPlayerDicePanel extends StatelessWidget {
  const LudoPlayerDicePanel({
    super.key,
    required this.myParticipant,
    required this.opponentParticipant,
    required this.myDiceValue,
    required this.opponentDiceValue,
    required this.myAnimateKey,
    required this.opponentAnimateKey,
    required this.myDiceState,
    required this.opponentDiceState,
    required this.onRollMine,
    this.preGame = false,
    this.headline,
    this.detail,
  });

  final LudoMatchParticipant myParticipant;
  final LudoMatchParticipant opponentParticipant;
  final int? myDiceValue;
  final int? opponentDiceValue;
  final int myAnimateKey;
  final int opponentAnimateKey;
  final LudoDiceVisualState myDiceState;
  final LudoDiceVisualState opponentDiceState;
  final VoidCallback onRollMine;
  final bool preGame;
  final String? headline;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final myColor = myParticipant.color ?? LudoColor.red;
    final opponentColor = opponentParticipant.color ?? LudoColor.green;
    final scheme = Theme.of(context).colorScheme;

    if (preGame) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'WHO STARTS?',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LabeledDice(
                label: opponentParticipant.displayLabel(myUserId: myParticipant.userId),
                color: opponentColor,
                value: opponentDiceValue,
                animateKey: opponentAnimateKey,
                state: opponentDiceState,
              ),
              const SizedBox(width: 28),
              _LabeledDice(
                label: 'You',
                color: myColor,
                value: myDiceValue,
                animateKey: myAnimateKey,
                state: myDiceState,
                onTap: myDiceState == LudoDiceVisualState.ready ? onRollMine : null,
              ),
            ],
          ),
          if (headline != null) ...[
            const SizedBox(height: 12),
            Text(
              headline!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LudoDice(
          value: myDiceValue,
          animateKey: myAnimateKey,
          state: myDiceState,
          onTap: myDiceState == LudoDiceVisualState.ready ? onRollMine : null,
          accentColor: myColor,
          size: 72,
          showRollHint: myDiceState == LudoDiceVisualState.ready,
        ),
        if (headline != null) ...[
          const SizedBox(height: 10),
          Text(
            headline!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
        if (detail != null) ...[
          const SizedBox(height: 2),
          Text(
            detail!,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _LabeledDice extends StatelessWidget {
  const _LabeledDice({
    required this.label,
    required this.color,
    required this.value,
    required this.animateKey,
    required this.state,
    this.onTap,
  });

  final String label;
  final LudoColor color;
  final int? value;
  final int animateKey;
  final LudoDiceVisualState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        LudoDice(
          value: value,
          animateKey: animateKey,
          state: state,
          onTap: onTap,
          accentColor: color,
          size: 56,
          showRollHint: state == LudoDiceVisualState.ready,
        ),
      ],
    );
  }
}
