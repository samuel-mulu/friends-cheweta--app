import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_socket.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';

const _mode = GameMode(
  id: 'mode-1',
  gameId: 'g',
  code: 'LUDO_1V1',
  name: 'Ludo',
  playerCount: 2,
  stakeAmountMinor: 100,
  platformFeeBps: 0,
  turnDurationSeconds: 30,
  rulesVersion: 'LUDO_CLASSIC_V1',
  enabled: true,
);

void main() {
  late FakeSocket socket;
  late ProviderContainer container;

  setUp(() {
    socket = FakeSocket();
    container = ProviderContainer(overrides: [
      gameSocketServiceProvider.overrideWithValue(socket),
      authControllerProvider.overrideWith(SignedInAs.new),
    ]);
  });
  tearDown(() => container.dispose());

  test('after leaving, a socket reconnect does not rejoin the lobby (no ghost presence)', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    await lobby.leave();
    socket.sent.clear();

    socket.statuses$.add(GameSocketStatus.connected);
    await flush();

    expect(socket.sent, isEmpty);
    expect(container.read(liveLobbyControllerProvider).mode, isNull);
  });

  test('while in the lobby, a socket reconnect rejoins it', () async {
    await container.read(liveLobbyControllerProvider.notifier).open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    socket.sent.clear();

    socket.statuses$.add(GameSocketStatus.connected);
    await flush();

    expect(socket.sent, ['lobby:join_game']);
  });

  test('accept ack alone is enough to enter the match', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    socket.events$.add(RealtimeEvent(name: 'challenge:received', payload: {
      'data': {'id': 'ch1', 'challengerId': 'other', 'opponentId': 'me', 'status': 'PENDING'},
    }));
    await flush();
    socket.reply = (event, _) => event == 'challenge:accept'
        ? {
            'ok': true,
            'data': {'id': 'ch1', 'status': 'ACCEPTED', 'match': {'id': 'match-9'}},
          }
        : {'ok': true};

    await lobby.accept();

    expect(container.read(liveLobbyControllerProvider).acceptedMatchId, 'match-9');
  });

  test('a cancelled challenge leaves us online until the server restores READY', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    socket.events$.add(RealtimeEvent(name: 'challenge:cancelled', payload: {
      'data': {'id': 'ch1', 'status': 'CANCELLED'},
    }));
    await flush();
    expect(container.read(liveLobbyControllerProvider).myState, LobbyPlayerState.online);

    socket.events$.add(RealtimeEvent(name: 'lobby:player_available', payload: {
      'data': {
        'player': {'userId': 'me', 'displayName': 'Me', 'state': 'READY'},
      },
    }));
    await flush();
    expect(container.read(liveLobbyControllerProvider).myState, LobbyPlayerState.ready);
  });

  test('invite: creating shows the code; joining returns the match to enter', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    socket.reply = (event, _) => switch (event) {
          'challenge:invite_create' => {
              'ok': true,
              'data': {'id': 'inv', 'kind': 'INVITE', 'challengerId': 'me', 'opponentId': '', 'inviteCode': 'ABCDEFGHJK'},
            },
          'challenge:invite_join' => {
              'ok': true,
              'data': {'id': 'inv', 'status': 'ACCEPTED', 'match': {'id': 'm-inv'}},
            },
          _ => {'ok': true},
        };

    await lobby.createInvite();
    final state = container.read(liveLobbyControllerProvider);
    expect(state.activeChallenge?.displayInviteCode, 'ABCDE-FGHJK');
    expect(state.myState, isNot(LobbyPlayerState.challenged));

    expect((await lobby.joinInvite('abcde-fghjk')).matchId, 'm-inv');
  });

  test('invite: a bad code surfaces a readable error', () async {
    socket.reply = (_, __) => {'ok': false, 'code': 'INVITE_NOT_FOUND'};
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    expect(() => lobby.joinInvite('nope1'), throwsA(isA<InviteJoinException>()));
  });

  test('rematch events are ignored by the lobby', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    socket.push('challenge:received', {'id': 'r1', 'kind': 'REMATCH', 'challengerId': 'other', 'opponentId': 'me'});
    await flush();
    expect(container.read(liveLobbyControllerProvider).activeChallenge, isNull);
  });

  test('Connect works while I am only online (server readies me in the same step)', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    expect(container.read(liveLobbyControllerProvider).myState, LobbyPlayerState.online);
    socket.sent.clear();

    await lobby.challenge(const LobbyPlayer(userId: 'sam', displayName: 'Sam', state: LobbyPlayerState.ready));

    expect(socket.sent, ['challenge:create']);
  });

  test('lobby chat badge: live messages from others count until the chat is opened', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.open('LUDO', stakes: const [_mode], stakeId: 'mode-1');
    void message(String id, String from) => socket.events$.add(RealtimeEvent(name: 'lobby:chat:message', payload: {
          'data': {'id': id, 'text': 'hi', 'sender': {'userId': from, 'displayName': from}},
        }));
    int unread() => container.read(liveLobbyControllerProvider).chatUnread;

    message('m1', 'other');
    message('m2', 'me'); // my own message is never unread
    await flush();
    expect(unread(), 1);

    lobby.setChatOpen(true);
    expect(unread(), 0);
    message('m3', 'other'); // read as it arrives
    await flush();
    expect(unread(), 0);

    lobby.setChatOpen(false);
    message('m4', 'other');
    await flush();
    expect(unread(), 1);
  });
}
