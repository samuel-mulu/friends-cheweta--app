import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/domain/auth_state.dart';
import 'package:friends_game_app/features/auth/domain/user.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';

class _FakeSocket extends Fake implements GameSocketService {
  final events$ = StreamController<RealtimeEvent>.broadcast();
  final statuses$ = StreamController<GameSocketStatus>.broadcast();
  final sent = <String>[];
  Map<String, dynamic> Function(String event, Map<String, dynamic> payload) reply =
      (_, __) => {'ok': true};

  @override
  Stream<RealtimeEvent> get events => events$.stream;
  @override
  Stream<GameSocketStatus> get statuses => statuses$.stream;
  @override
  Future<Map<String, dynamic>> emitWithAck(String event, [Map<String, dynamic> payload = const {}]) async {
    sent.add(event);
    return reply(event, payload);
  }
}

class _SignedIn extends AuthController {
  @override
  AuthState build() => const AuthState(
        status: AuthStatus.authenticated,
        user: User(id: 'me', fullName: 'Me', phoneNumber: '0', role: 'PLAYER', status: 'ACTIVE'),
      );
}

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
  late _FakeSocket socket;
  late ProviderContainer container;

  setUp(() {
    socket = _FakeSocket();
    container = ProviderContainer(overrides: [
      gameSocketServiceProvider.overrideWithValue(socket),
      authControllerProvider.overrideWith(_SignedIn.new),
    ]);
  });
  tearDown(() => container.dispose());

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('after leaving, a socket reconnect does not rejoin the lobby (no ghost presence)', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.join(_mode);
    await lobby.leave();
    socket.sent.clear();

    socket.statuses$.add(GameSocketStatus.connected);
    await flush();

    expect(socket.sent, isEmpty);
    expect(container.read(liveLobbyControllerProvider).mode, isNull);
  });

  test('while in the lobby, a socket reconnect rejoins it', () async {
    await container.read(liveLobbyControllerProvider.notifier).join(_mode);
    socket.sent.clear();

    socket.statuses$.add(GameSocketStatus.connected);
    await flush();

    expect(socket.sent, ['lobby:join']);
  });

  test('accept ack alone is enough to enter the match', () async {
    final lobby = container.read(liveLobbyControllerProvider.notifier);
    await lobby.join(_mode);
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
    await lobby.join(_mode);
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
}
