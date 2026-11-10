import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_challenge.dart';
import 'package:friends_game_app/features/match/application/practice_launcher.dart';
import 'support/fake_socket.dart';

void main() {
  test('routes are derived from the game code', () {
    expect(GameRoutes.lobby(GameCodes.dama), '/dama');
    expect(GameRoutes.match(GameCodes.dama, 'm1'), '/dama/match/m1');
    expect(GameRoutes.result(GameCodes.ludo, 'm1'), '/ludo/result/m1');
    expect(GameRoutes.displayName(GameCodes.dama), 'Dama');
  });

  test('the game of a match is read from server payloads', () {
    expect(gameCodeOfMatch({'id': 'm', 'game': {'code': 'DAMA'}}), 'DAMA');
    expect(gameCodeOfMatch({'id': 'm'}), isNull);
    final challenge = LobbyChallenge.fromJson({
      'id': 'c',
      'match': {'id': 'm1', 'game': {'code': 'DAMA'}},
    });
    expect(challenge.matchId, 'm1');
    expect(challenge.matchGameCode, 'DAMA');
    expect(GameMode.fromJson({'id': 'x'}).withGameCode('DAMA').gameCode, 'DAMA');
  });

  test('Dama practice asks for the game and opens whichever game was started', () async {
    final socket = FakeSocket();
    Map<String, dynamic>? sent;
    socket.reply = (event, payload) {
      sent = payload;
      // The server resumed an unfinished Ludo practice game instead.
      return {'ok': true, 'data': {'matchId': 'pm-9', 'gameCode': 'LUDO', 'resumed': true}};
    };
    final container = ProviderContainer(overrides: [gameSocketServiceProvider.overrideWithValue(socket)]);
    addTearDown(container.dispose);

    final started = await container.read(practiceLauncherProvider).start(PracticeLevel.hard, gameCode: GameCodes.dama);
    expect(sent?['game'], 'DAMA');
    expect(sent?.containsKey('tokensToWin'), isFalse);
    expect(started, (matchId: 'pm-9', gameCode: 'LUDO'));
  });
}
