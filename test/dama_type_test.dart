import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';

GameMode _stake(String id, int etb, String rules, {bool custom = false}) => GameMode(
      id: id,
      gameId: 'dama',
      code: id,
      name: id,
      playerCount: 2,
      stakeAmountMinor: etb * 100,
      platformFeeBps: 0,
      turnDurationSeconds: 40,
      rulesVersion: rules,
      enabled: true,
      gameCode: 'DAMA',
      custom: custom,
    );

const _tank = 'DAMA_ET_V1';
const _egr = 'DAMA_ET_FORWARD_V1';

void main() {
  group('DamaType', () {
    test('maps rules versions both ways', () {
      expect(DamaType.parse(_egr), DamaType.egregna);
      expect(DamaType.parse(_tank), DamaType.tankegna);
      expect(DamaType.egregna.rulesVersion, _egr);
      expect(DamaType.egregna.name, 'እግረኛ');
      expect(DamaType.tankegna.name, 'ታንከኛ');
    });

    test('unknown or missing versions are the classic ታንከኛ (tryParse: null)', () {
      expect(DamaType.parse(null), DamaType.tankegna);
      expect(DamaType.parse('LUDO_CLASSIC_V3'), DamaType.tankegna);
      expect(DamaType.tryParse('LUDO_CLASSIC_V3'), isNull);
    });

    test('a game reads its type from the server state', () {
      final game = DamaGame.fromJson({'matchId': 'm', 'rulesVersion': _egr, 'players': const []});
      expect(game.type, DamaType.egregna);
      expect(game.copyWith(version: 2).type, DamaType.egregna);
      expect(DamaGame.fromJson({'matchId': 'm'}).type, DamaType.tankegna);
    });
  });

  group('Lobby by type', () {
    final stakes = [
      _stake('t50', 50, _tank),
      _stake('t100', 100, _tank),
      _stake('e100', 100, _egr),
      _stake('e200', 200, _egr),
      _stake('e-custom', 75, _egr, custom: true),
    ];
    LiveLobbyState lobby({String? me, List<LobbyPlayer> players = const []}) => LiveLobbyState(
          gameCode: 'DAMA',
          stakes: stakes,
          myStakeId: me,
          currentUserId: 'me',
          players: players,
        );

    test('offers both types only when the catalog has both', () {
      expect(lobby().offersAll([_tank, _egr]), isTrue);
      expect(LiveLobbyState(stakes: [stakes[0]]).offersAll([_tank, _egr]), isFalse);
    });

    test('switching keeps the amount when the other type has it, else its smallest', () {
      expect(lobby(me: 't100').stakeForRules(_egr, amountMinor: 10000)?.id, 'e100');
      expect(lobby(me: 't50').stakeForRules(_egr, amountMinor: 5000)?.id, 'e100');
      expect(lobby().stakeForRules(_tank)?.id, 't50');
      expect(lobby().stakeForRules('NOPE'), isNull);
    });

    test('lists stakes and counts ready players per type (never me)', () {
      final state = lobby(me: 't100', players: const [
        LobbyPlayer(userId: 'a', displayName: 'A', state: LobbyPlayerState.ready, gameModeId: 'e200'),
        LobbyPlayer(userId: 'b', displayName: 'B', state: LobbyPlayerState.ready, gameModeId: 't50'),
        LobbyPlayer(userId: 'c', displayName: 'C', state: LobbyPlayerState.online, gameModeId: 'e100'),
        LobbyPlayer(userId: 'me', displayName: 'Me', state: LobbyPlayerState.ready, gameModeId: 't100'),
      ]);
      expect(state.myRules, _tank);
      expect(state.stakesOfRules(_egr).map((s) => s.id), ['e100', 'e200']); // empty custom stake hidden
      expect(state.readyCountOfRules(_egr), 1);
      expect(state.readyCountOfRules(_tank), 1);
    });
  });
}
