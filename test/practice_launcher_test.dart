import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/match/application/practice_launcher.dart';
import 'support/fake_socket.dart';

void main() {
  late FakeSocket socket;
  late ProviderContainer container;

  setUp(() {
    socket = FakeSocket();
    container = ProviderContainer(overrides: [gameSocketServiceProvider.overrideWithValue(socket)]);
  });
  tearDown(() => container.dispose());

  test('starting practice returns the match and remembers the level for "Play again"', () async {
    socket.reply = (event, payload) => event == 'practice:start' && payload['level'] == 'HARD'
        ? {'ok': true, 'data': {'matchId': 'pm-1', 'level': 'HARD'}}
        : {'ok': false};

    expect((await container.read(practiceLauncherProvider).start(PracticeLevel.hard)).matchId, 'pm-1');
    expect(container.read(lastPracticeLevelProvider), PracticeLevel.hard);
  });

  test('a paid match in progress gives a clear message', () async {
    socket.reply = (_, __) => {'ok': false, 'code': 'LOBBY_ACTIVE_MATCH', 'message': 'x'};
    expect(
      () => container.read(practiceLauncherProvider).start(PracticeLevel.easy),
      throwsA(isA<PracticeStartException>().having((e) => e.message, 'message', 'Finish your current match first.')),
    );
  });
}
