import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/ludo/application/match_reactions_controller.dart';
import 'support/fake_socket.dart';

void main() {
  late FakeSocket socket;
  late ProviderContainer container;

  setUp(() {
    socket = FakeSocket();
    container = ProviderContainer(overrides: [gameSocketServiceProvider.overrideWithValue(socket)]);
  });
  tearDown(() => container.dispose());

  test('every reaction id matches the server whitelist', () {
    expect(MatchReaction.values.map((r) => r.id), [
      'good_luck', 'nice_move', 'hurry_up', 'oops', 'thanks', 'gg', //
      'thumbs_up', 'laugh', 'angry', 'wow', 'party', 'pray',
    ]);
  });

  test('a reaction shows on the sender for a moment, only for the current match', () {
    fakeAsync((async) {
      container.read(matchReactionsProvider.notifier).attach('m1');
      socket.push('match:reaction', {'userId': 'sam', 'reactionId': 'nice_move'}, matchId: 'm1');
      socket.push('match:reaction', {'userId': 'eve', 'reactionId': 'gg'}, matchId: 'other');
      async.flushMicrotasks();

      final shown = container.read(matchReactionsProvider);
      expect(shown.keys, ['sam']);
      expect(shown['sam']!.reaction.display, 'Nice move!');

      async.elapse(MatchReactionsController.visibleFor + const Duration(milliseconds: 10));
      expect(container.read(matchReactionsProvider), isEmpty);
    });
  });

  test('sending emits match:reaction for the attached match', () async {
    final payloads = <Map<String, dynamic>>[];
    socket.reply = (event, payload) {
      if (event == 'match:reaction') payloads.add(payload);
      return {'ok': true};
    };
    container.read(matchReactionsProvider.notifier).attach('m1');
    await container.read(matchReactionsProvider.notifier).send(MatchReaction.party);
    expect(payloads.single, {'matchId': 'm1', 'reactionId': 'party'});
  });
}
