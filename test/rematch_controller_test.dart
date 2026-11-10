import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/match/application/rematch_controller.dart';
import 'support/fake_socket.dart';

Map<String, dynamic> _offer({String challenger = 'me', String opponent = 'other', String source = 'old'}) => {
      'id': 'r1',
      'kind': 'REMATCH',
      'sourceMatchId': source,
      'challengerId': challenger,
      'opponentId': opponent,
      'status': 'PENDING',
    };

void main() {
  late FakeSocket socket;
  late ProviderContainer container;
  RematchController controller() => container.read(rematchControllerProvider.notifier);
  RematchState state() => container.read(rematchControllerProvider);

  setUp(() {
    socket = FakeSocket();
    container = ProviderContainer(overrides: [
      gameSocketServiceProvider.overrideWithValue(socket),
      authControllerProvider.overrideWith(SignedInAs.new),
    ]);
  });
  tearDown(() => container.dispose());

  test('recovers a pending rematch for this match after reconnect', () async {
    socket.reply = (event, _) =>
        event == 'challenge:active' ? {'ok': true, 'data': _offer(challenger: 'other', opponent: 'me')} : {'ok': true};
    await controller().attach('old');
    expect(state().offer?.id, 'r1');
  });

  test('ignores a pending rematch that belongs to a different match', () async {
    socket.reply = (_, __) => {'ok': true, 'data': _offer(source: 'another')};
    await controller().attach('old');
    expect(state().offer, isNull);
  });

  test('request, then the opponent accepts: enter the new match', () async {
    socket.reply = (event, _) => event == 'challenge:rematch' ? {'ok': true, 'data': _offer()} : {'ok': true};
    await controller().attach('old');
    await controller().request();
    expect(state().offer?.id, 'r1');

    socket.push('challenge:accepted', {
      ..._offer(),
      'status': 'ACCEPTED',
      'match': {'id': 'new-1'},
    });
    await flush();
    expect(state().newMatchId, 'new-1');
  });

  test('accepting an incoming offer uses the match id from the ack', () async {
    socket.reply = (event, _) => switch (event) {
          'challenge:active' => {'ok': true, 'data': _offer(challenger: 'other', opponent: 'me')},
          'challenge:accept' => {
              'ok': true,
              'data': {
                ..._offer(),
                'status': 'ACCEPTED',
                'match': {'id': 'new-2'},
              },
            },
          _ => {'ok': true},
        };
    await controller().attach('old');
    await controller().accept();
    expect(state().newMatchId, 'new-2');
  });

  test('a declined offer clears with a message', () async {
    socket.reply = (_, __) => {'ok': true, 'data': _offer()};
    await controller().attach('old');
    socket.push('challenge:rejected', {..._offer(), 'status': 'REJECTED'});
    await flush();
    expect(state().offer, isNull);
    expect(state().message, 'Rematch declined.');
  });
}
