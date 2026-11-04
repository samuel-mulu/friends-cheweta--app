import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';
import 'support/fake_socket.dart';

Map<String, dynamic> _ack({List<Map<String, dynamic>> legalMoves = const []}) => {
      'ok': true,
      'state': {
        'game': {
          'matchId': 'm1',
          'version': 5,
          'phase': 'PLAYING',
          'turnPhase': legalMoves.isEmpty ? 'WAITING_FOR_ROLL' : 'WAITING_FOR_MOVE',
          'currentPlayerId': 'me',
          'diceValue': legalMoves.isEmpty ? null : 6,
          'legalTokenIds': [for (final m in legalMoves) m['tokenId']],
          'players': [],
        },
        'startingRoll': {'round': 1, 'candidatePlayerIds': [], 'rolls': {}},
        'resignedPlayerIds': [],
      },
      'timing': {
        'matchId': 'm1',
        'version': 5,
        'turnPhase': 'WAITING_FOR_ROLL',
        'consecutiveTimeoutsByPlayer': {'p2': 1},
      },
      'participants': [],
      'legalMoves': legalMoves,
    };

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
  tearDown(() {
    LudoMotion.speed = 1.0;
    container.dispose();
  });

  LudoMatchViewState state() => container.read(ludoMatchControllerProvider);

  test('landing preview comes from the join ack and clears when the turn moves on', () async {
    socket.reply = (_, __) => _ack(legalMoves: [
          {'tokenId': 'RED-1', 'toProgress': 8, 'captures': [], 'safe': true},
        ]);
    await container.read(ludoMatchControllerProvider.notifier).join('m1');
    expect(state().legalMoves.single.toProgress, 8);

    socket.push('ludo:turn_started', {'type': 'TURN_STARTED', 'playerId': 'p2'}, matchId: 'm1', version: 6);
    await flush();
    expect(state().legalMoves, isEmpty);
  });

  test('strikes are seeded from timing, raised by auto-play, and reset when the player returns', () async {
    socket.reply = (_, __) => _ack();
    await container.read(ludoMatchControllerProvider.notifier).join('m1');
    expect(state().strikes['p2'], 1);

    socket.push('ludo:auto_played', {'playerId': 'p2', 'strikes': 2, 'maxStrikes': 3}, matchId: 'm1');
    await flush();
    expect(state().strikes['p2'], 2);
    expect(state().autoPlayNotice?.playerId, 'p2');

    socket.push('ludo:strikes', {'playerId': 'p2', 'strikes': 0, 'maxStrikes': 3}, matchId: 'm1');
    await flush();
    expect(state().strikes['p2'], 0);
  });

  test('fast animations shorten every presentation duration', () async {
    final normal = LudoMotion.diceRoll;
    await container.read(playerPreferencesProvider.notifier).setFastAnimations(true);
    expect(LudoMotion.diceRoll.inMilliseconds, (normal.inMilliseconds * 0.6).round());
    expect(container.read(playerPreferencesProvider).fastAnimations, isTrue);
  });
}
