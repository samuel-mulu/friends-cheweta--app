import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/history/domain/match_history.dart';

void main() {
  test('parses backend match history with bigint strings and settlement', () {
    final match = MatchHistoryItem.fromJson({
      'id': 'm1',
      'status': 'FINISHED',
      'stakeAmountMinor': '1000',
      'createdAt': '2026-08-24T10:00:00.000Z',
      'game': {'code': 'LUDO', 'name': 'Ludo'},
      'gameMode': {'code': 'LUDO_1V1_10', 'name': 'Ludo 1v1 · 10 ETB'},
      'winnerOrder': ['u1', 'u2'],
      'participants': [
        {'userId': 'u1', 'seat': 0, 'resultPosition': 1, 'user': {'fullName': 'A'}},
        {'userId': 'u2', 'seat': 1, 'resultPosition': 2, 'user': {'fullName': 'B'}},
      ],
      'settlement': {
        'winnerUserId': 'u1',
        'potAmountMinor': '2000',
        'platformFeeMinor': '200',
        'payoutAmountMinor': '1800',
        'settledAt': '2026-08-24T10:30:00.000Z',
      },
    });

    expect(match.stakeAmountMinor, 1000);
    expect(match.participant('u1')?.resultPosition, 1);
    expect(match.settlement?.payoutAmountMinor, 1800);
  });
}
