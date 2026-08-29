import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

void main() {
  test('parses authoritative B9 runtime snapshot', () {
    final snapshot = LudoRuntimeSnapshot.fromJson({
      'game': {
        'rulesVersion': 'LUDO_CLASSIC_V1',
        'matchId': 'match-1',
        'version': 12,
        'phase': 'PLAYING',
        'turnPhase': 'WAITING_FOR_MOVE',
        'players': [
          {
            'userId': 'a',
            'color': 'RED',
            'tokens': [
              {'id': 'RED-1', 'ownerId': 'a', 'color': 'RED', 'state': 'ACTIVE', 'progress': 8}
            ],
          },
          {
            'userId': 'b',
            'color': 'YELLOW',
            'tokens': [
              {'id': 'YELLOW-1', 'ownerId': 'b', 'color': 'YELLOW', 'state': 'BASE', 'progress': -1}
            ],
          },
        ],
        'currentPlayerId': 'a',
        'diceValue': 4,
        'consecutiveSixes': 0,
        'legalTokenIds': ['RED-1'],
        'winnerOrder': [],
      },
      'startingRoll': {
        'round': 1,
        'candidatePlayerIds': ['a', 'b'],
        'rolls': {'a': 6, 'b': 3},
      },
      'resignedPlayerIds': [],
    });

    expect(snapshot.game.version, 12);
    expect(snapshot.game.turnPhase, LudoTurnPhase.waitingForMove);
    expect(snapshot.game.players.first.color, LudoColor.red);
    expect(snapshot.game.legalTokenIds, ['RED-1']);
    expect(snapshot.startingRoll.rolls['a'], 6);
  });

  test('parses exact server timing state', () {
    final timing = LudoTimingState.fromJson({
      'matchId': 'match-1',
      'version': 12,
      'playerId': 'a',
      'turnPhase': 'WAITING_FOR_MOVE',
      'turnEndsAt': '2026-08-24T12:00:30.000Z',
      'consecutiveTimeoutsByPlayer': {'a': 1},
    });

    expect(timing.version, 12);
    expect(timing.turnEndsAt, DateTime.parse('2026-08-24T12:00:30.000Z'));
    expect(timing.consecutiveTimeoutsByPlayer['a'], 1);
    expect(timing.estimated, isFalse);
  });
}
