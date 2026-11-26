import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_socket.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';
import 'package:friends_game_app/features/requests/request_center.dart';

GameMode _stake(String id, int minor) => GameMode(
      id: id,
      gameId: 'ludo',
      code: id,
      name: id,
      playerCount: 2,
      stakeAmountMinor: minor,
      platformFeeBps: 500,
      turnDurationSeconds: 30,
      rulesVersion: 'LUDO_CLASSIC_V3',
      enabled: true,
    );

final _ten = _stake('s10', 1000);
final _twenty = _stake('s20', 2000);

void main() {
  late FakeSocket socket;
  late ProviderContainer container;
  final joins = <Map<String, dynamic>>[];

  /// The server's view of the lobby: me at [mine], Abel ready at 20, Sara online at 10.
  Map<String, dynamic> snapshot(String mine, {String myState = 'ONLINE'}) => {
        'ok': true,
        'data': {
          'gameModeId': mine,
          'myState': myState,
          'players': [
            {'userId': 'me', 'displayName': 'Me', 'state': myState, 'gameModeId': mine},
            {'userId': 'abel', 'displayName': 'Abel', 'state': 'READY', 'gameModeId': 's20', 'readyAt': '2026-11-17T08:00:00Z'},
            {'userId': 'sara', 'displayName': 'Sara', 'state': 'ONLINE', 'gameModeId': 's10'},
          ],
        },
      };

  setUp(() {
    joins.clear();
    socket = FakeSocket();
    socket.reply = (event, payload) {
      if (event == 'lobby:join_game') {
        joins.add(payload);
        return snapshot(payload['gameModeId']?.toString() ?? 's10');
      }
      return {'ok': true};
    };
    container = ProviderContainer(overrides: [
      gameSocketServiceProvider.overrideWithValue(socket),
      authControllerProvider.overrideWith(SignedInAs.new),
    ]);
  });
  tearDown(() => container.dispose());

  LiveLobbyController lobby() => container.read(liveLobbyControllerProvider.notifier);
  LiveLobbyState state() => container.read(liveLobbyControllerProvider);

  test('opening a game lists players at every stake, each with their stake', () async {
    await lobby().open('LUDO', stakes: [_twenty, _ten]);

    expect(state().stakes.map((s) => s.id), ['s10', 's20']); // smallest first
    expect(state().myStakeId, 's10');
    expect(state().visiblePlayers.map((p) => '${p.userId}@${p.gameModeId}'), ['abel@s20', 'sara@s10']);
    expect(state().readyCount, 1);
    expect(state().readyCountAt('s20'), 1);
    expect(state().readyCountAt('s10'), 0);
  });

  test('the stake filter narrows the list without moving me', () async {
    await lobby().open('LUDO', stakes: [_ten, _twenty]);
    lobby().setFilter('s10');
    expect(state().visiblePlayers.map((p) => p.userId), ['sara']);
    expect(state().myStakeId, 's10');
    lobby().setFilter(null);
    expect(state().visiblePlayers, hasLength(2));
  });

  test('playing someone at another stake moves me to their stake first, then sends the request', () async {
    await lobby().open('LUDO', stakes: [_ten, _twenty]);
    socket.sent.clear();

    final abel = state().visiblePlayers.firstWhere((p) => p.userId == 'abel');
    await lobby().challenge(abel);

    expect(socket.sent, ['lobby:join_game', 'challenge:create']);
    expect(joins.last['gameModeId'], 's20');
    expect(state().myStakeId, 's20');
  });

  test('changing my stake while ready keeps me ready', () async {
    socket.reply = (event, payload) => switch (event) {
          'lobby:join_game' => snapshot(payload['gameModeId']?.toString() ?? 's10', myState: payload['gameModeId'] == null ? 'READY' : 'ONLINE'),
          _ => {'ok': true},
        };
    await lobby().open('LUDO', stakes: [_ten, _twenty]);
    expect(state().isReady, isTrue);
    socket.sent.clear();

    await lobby().changeStake('s20');

    expect(socket.sent, ['lobby:join_game', 'lobby:ready']);
  });

  test('lobby events from another game are ignored; a player moving stake stays listed', () async {
    await lobby().open('LUDO', stakes: [_ten, _twenty]);

    socket.push('lobby:player_joined', {'gameModeId': 'dama-10', 'player': {'userId': 'x', 'displayName': 'X', 'state': 'READY'}});
    await flush();
    expect(state().players.any((p) => p.userId == 'x'), isFalse);

    // Sara moves from 10 to 20: the server says "left 10", then "joined 20".
    socket.push('lobby:player_left', {'gameModeId': 's10', 'player': {'userId': 'sara'}});
    socket.push('lobby:player_joined', {'gameModeId': 's20', 'player': {'userId': 'sara', 'displayName': 'Sara', 'state': 'ONLINE', 'gameModeId': 's20'}});
    await flush();
    expect(state().players.firstWhere((p) => p.userId == 'sara').gameModeId, 's20');
  });

  group('custom stakes', () {
    test('a player at a new custom stake adds its chip at once; it hides when they leave', () async {
      await lobby().open('LUDO', stakes: [_ten, _twenty]);
      socket.push('lobby:player_joined', {
        'gameModeId': 'c500',
        'player': {'userId': 'dawit', 'displayName': 'Dawit', 'state': 'READY', 'gameModeId': 'c500', 'stakeAmountMinor': '50000'},
      });
      await flush();
      final custom = state().visibleStakes.last;
      expect(custom.stakeAmountMinor, 50000);
      expect(custom.custom, isTrue);
      expect(state().readyCountAt('c500'), 1);

      socket.push('lobby:player_left', {'gameModeId': 'c500', 'player': {'userId': 'dawit'}});
      await flush();
      expect(state().visibleStakes.map((s) => s.id), ['s10', 's20']);
    });

    test('choosing an amount sends it to the server; a ready player stays ready', () async {
      final sent = <Map<String, dynamic>>[];
      socket.reply = (event, payload) {
        if (event != 'lobby:join_game') return {'ok': true};
        sent.add(payload);
        final custom = payload['customStakeMinor'] != null;
        return {
          'ok': true,
          'data': {
            'gameModeId': custom ? 'c500' : 's10',
            'myState': custom ? 'ONLINE' : 'READY',
            'stakes': [
              {'id': 's10', 'code': 'L10', 'name': 'L', 'stakeAmountMinor': '1000', 'playerCount': 2, 'platformFeeBps': 0, 'turnDurationSeconds': 30, 'rulesVersion': 'V3', 'custom': false},
              if (custom)
                {'id': 'c500', 'code': 'LC', 'name': 'L', 'stakeAmountMinor': '50000', 'playerCount': 2, 'platformFeeBps': 0, 'turnDurationSeconds': 30, 'rulesVersion': 'V3', 'custom': true},
            ],
            'players': [],
          },
        };
      };
      await lobby().open('LUDO', stakes: [_ten, _twenty]);
      expect(state().stakes.map((s) => s.id), ['s10']); // the server's list wins
      socket.sent.clear();

      await lobby().playCustomStake(50000);

      expect(sent.last['customStakeMinor'], 50000);
      expect(sent.last.containsKey('gameModeId'), isFalse);
      expect(state().myStake?.stakeAmountMinor, 50000);
      expect(socket.sent, ['lobby:join_game', 'lobby:ready']);
    });
  });

  group('request center', () {
    RequestCenterState requests() => container.read(requestCenterProvider);

    test('an incoming request is held app-wide; accepting opens the match', () async {
      container.read(requestCenterProvider); // start listening
      socket.push('challenge:received', {'id': 'c1', 'kind': 'LOBBY', 'challengerId': 'abel', 'opponentId': 'me', 'challengerName': 'Abel', 'gameModeId': 's20'});
      await flush();
      expect(requests().request?.id, 'c1');
      expect(requests().isIncomingFor('me'), isTrue);

      socket.reply = (event, _) => event == 'challenge:accept'
          ? {'ok': true, 'data': {'id': 'c1', 'status': 'ACCEPTED', 'match': {'id': 'm1', 'game': {'code': 'LUDO'}}}}
          : {'ok': true};
      await container.read(requestCenterProvider.notifier).accept();

      expect(requests().request, isNull);
      expect(requests().openMatch?.matchId, 'm1');
      expect(requests().openMatch?.gameCode, 'LUDO');
    });

    test('my request being declined clears it with a notice', () async {
      container.read(requestCenterProvider);
      socket.push('challenge:created', {'id': 'c2', 'challengerId': 'me', 'opponentId': 'abel', 'opponentName': 'Abel'});
      await flush();
      expect(requests().request?.id, 'c2');

      socket.push('challenge:rejected', {'id': 'c2', 'status': 'REJECTED'});
      await flush();
      expect(requests().request, isNull);
      expect(requests().notice, 'Abel declined.');
    });

    test('invites and my own rematch offers are not shown as requests', () async {
      container.read(requestCenterProvider);
      socket.push('challenge:created', {'id': 'i1', 'kind': 'INVITE', 'challengerId': 'me', 'opponentId': ''});
      socket.push('challenge:created', {'id': 'r1', 'kind': 'REMATCH', 'challengerId': 'me', 'opponentId': 'abel'});
      await flush();
      expect(requests().request, isNull);

      socket.push('challenge:received', {'id': 'r2', 'kind': 'REMATCH', 'challengerId': 'abel', 'opponentId': 'me'});
      await flush();
      expect(requests().request?.id, 'r2');
    });
  });

  test('a player state change keeps their stake', () {
    const player = LobbyPlayer(userId: 'a', displayName: 'A', state: LobbyPlayerState.online, gameModeId: 's10');
    expect(player.copyWith(state: LobbyPlayerState.ready).gameModeId, 's10');
  });
}
