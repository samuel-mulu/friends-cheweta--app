import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';

void main() {
  test('winner payout uses player pot minus snapshotted fee basis points', () {
    final mode = GameMode.fromJson({
      'id': 'm1',
      'gameId': 'g1',
      'code': 'LUDO_1V1_10',
      'name': 'Ludo 1v1 - 10 ETB',
      'playerCount': 2,
      'stakeAmountMinor': '1000',
      'platformFeeBps': 1000,
      'turnDurationSeconds': 30,
      'rulesVersion': 'LUDO_CLASSIC_V1',
      'enabled': true,
    });

    expect(mode.totalPotMinor, 2000);
    expect(mode.estimatedFeeMinor, 200);
    expect(mode.estimatedWinnerPayoutMinor, 1800);
  });
}
