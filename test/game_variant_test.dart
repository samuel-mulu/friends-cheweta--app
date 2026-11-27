import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

GameMode _stake(String id, int etb, String rules, {bool custom = false, String game = 'DAMA'}) => GameMode(
      id: id,
      gameId: game.toLowerCase(),
      code: id,
      name: id,
      playerCount: 2,
      stakeAmountMinor: etb * 100,
      platformFeeBps: 0,
      turnDurationSeconds: 40,
      rulesVersion: rules,
      enabled: true,
      gameCode: game,
      custom: custom,
    );

const _tank = 'DAMA_ET_V1';
const _egr = 'DAMA_ET_FORWARD_V1';

void main() {
  group('GameVariants', () {
    test('each game lists its types; one is the classic default', () {
      expect(GameVariants.of('DAMA').map((v) => v.name), ['እግረኛ', 'ታንከኛ']);
      expect(GameVariants.of('LUDO').map((v) => v.name), ['መመለስ ያለበት', 'መመለስ የሌለበት', 'መመለስ የረሳ ይሸነፋል']);
      expect(GameVariants.of('KARTA'), isEmpty);
      expect(GameVariants.defaultOf('DAMA'), GameVariants.damaClassic);
      expect(GameVariants.defaultOf('LUDO'), GameVariants.ludoClassic);
    });

    test('maps rules versions both ways; older versions resolve to the classic type', () {
      expect(GameVariants.find(_egr), GameVariants.damaForward);
      expect(GameVariants.find('LUDO_NO_CAPTURE_V1'), GameVariants.ludoNoCapture);
      expect(GameVariants.find('LUDO_CLASSIC_V2'), isNull);
      expect(GameVariants.resolve('LUDO', 'LUDO_CLASSIC_V2'), GameVariants.ludoClassic);
      expect(GameVariants.resolve('DAMA', null), GameVariants.damaClassic);
      // A type of another game never leaks in.
      expect(GameVariants.resolve('DAMA', 'LUDO_NO_CAPTURE_V1'), GameVariants.damaClassic);
    });

    test('a Dama game reads its type from the server state', () {
      final game = DamaGame.fromJson({'matchId': 'm', 'rulesVersion': _egr, 'players': const []});
      expect(game.variant, GameVariants.damaForward);
      expect(game.copyWith(version: 2).variant, GameVariants.damaForward);
      expect(DamaGame.fromJson({'matchId': 'm'}).variant, GameVariants.damaClassic);
    });

    test('preferences open each game on its last type', () {
      const prefs = PlayerPreferences(variantByGame: {'LUDO': 'LUDO_MISSED_CAPTURE_V1'});
      expect(prefs.variantFor('LUDO'), GameVariants.ludoMissedCapture);
      expect(prefs.variantFor('DAMA'), GameVariants.damaClassic);
      expect(prefs.variantFor('KARTA'), isNull);
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

    test('offers the types that have stakes (a picker from two)', () {
      expect(lobby().offeredVariants, [GameVariants.damaForward, GameVariants.damaClassic]);
      expect(lobby(me: 'e100').myVariant, GameVariants.damaForward);
      final oneType = LiveLobbyState(gameCode: 'DAMA', stakes: [stakes[0]], myStakeId: 't50');
      expect(oneType.offeredVariants, [GameVariants.damaClassic]);
      expect(oneType.myVariant, isNull);
      final ludo = LiveLobbyState(gameCode: 'LUDO', stakes: [
        _stake('l10', 10, 'LUDO_CLASSIC_V3', game: 'LUDO'),
        _stake('m10', 10, 'LUDO_MISSED_CAPTURE_V1', game: 'LUDO'),
      ]);
      expect(ludo.offeredVariants, [GameVariants.ludoClassic, GameVariants.ludoMissedCapture]);
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

  test('a lobby player carries what they asked for when ready (goal, auto-match)', () {
    final ready = LobbyPlayer.fromJson({'userId': 'a', 'state': 'READY', 'tokensToWin': 2, 'autoMatch': false});
    expect(ready.tokensToWin, 2);
    expect(ready.autoMatch, isFalse);
    expect(ready.copyWith(state: LobbyPlayerState.challenged).tokensToWin, 2);
    final online = LobbyPlayer.fromJson({'userId': 'b', 'state': 'ONLINE', 'tokensToWin': 9});
    expect(online.tokensToWin, isNull); // out of range is ignored
    expect(online.autoMatch, isNull);
  });
}
