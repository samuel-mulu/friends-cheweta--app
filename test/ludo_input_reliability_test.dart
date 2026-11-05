import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_token.dart';
import 'support/fake_socket.dart';

Map<String, dynamic> _joinAck() => {
      'ok': true,
      'state': {
        'game': {
          'matchId': 'm1',
          'version': 5,
          'phase': 'PLAYING',
          'turnPhase': 'WAITING_FOR_ROLL',
          'currentPlayerId': 'me',
          'legalTokenIds': [],
          'players': [],
        },
        'startingRoll': {'round': 1, 'candidatePlayerIds': [], 'rolls': {}},
        'resignedPlayerIds': [],
      },
      'timing': {'matchId': 'm1', 'version': 5, 'turnPhase': 'WAITING_FOR_ROLL', 'consecutiveTimeoutsByPlayer': {}},
      'participants': [],
    };

Widget _board(List<LudoBoardTokenView> tokens, {VoidCallback? onBoardTap}) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 300, height: 300, child: LudoBoard(tokens: tokens, onBoardTap: onBoardTap)),
      ),
    );

Finder get _movable => find.byWidgetPredicate((w) => w is LudoTokenPiece && w.onTap != null);
Finder get _idle => find.byWidgetPredicate((w) => w is LudoTokenPiece && w.onTap == null);

void main() {
  group('board taps', () {
    testWidgets('an idle token never swallows a tap; the board explains instead', (tester) async {
      var boardTaps = 0;
      await tester.pumpWidget(_board(
        const [LudoBoardTokenView(id: 'YELLOW-1', color: LudoColor.yellow, progress: 5, baseIndex: 0)],
        onBoardTap: () => boardTaps++,
      ));
      await tester.tap(_idle, warnIfMissed: false);
      expect(boardTaps, 1);
    });

    testWidgets('a movable token is painted on top and has a comfortable touch target', (tester) async {
      var moved = 0;
      await tester.pumpWidget(_board([
        LudoBoardTokenView(
          id: 'RED-1',
          color: LudoColor.red,
          progress: 3,
          baseIndex: 0,
          highlighted: true,
          onTap: () => moved++,
        ),
        // Listed after the movable one: before, it was painted (and hit-tested) on top.
        const LudoBoardTokenView(id: 'RED-2', color: LudoColor.red, progress: 3, baseIndex: 1, stackIndex: 1, stackCount: 2),
      ]));
      final target = tester.getSize(find.descendant(of: _movable, matching: find.byType(GestureDetector)).first);
      expect(target.shortestSide, greaterThanOrEqualTo(LudoBoard.minHit));
      // Tapping near the edge of the target, not the pin's exact centre, still moves.
      await tester.tapAt(tester.getCenter(_movable) + const Offset(14, 14));
      expect(moved, 1);
    });
  });

  group('presentation queue', () {
    late ProviderContainer container;
    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('turn notices never block input; dice and moves do', () {
      fakeAsync((async) {
        final queue = container.read(ludoAnimationQueueProvider.notifier);
        queue.enqueue(const LudoPresentationEvent(kind: LudoPresentationKind.turn, playerId: 'me'));
        expect(container.read(ludoAnimationQueueProvider).blocking, isFalse);
        queue.enqueue(const LudoPresentationEvent(kind: LudoPresentationKind.dice, playerId: 'me', diceValue: 4));
        expect(container.read(ludoAnimationQueueProvider).blocking, isTrue); // queued dice blocks
        async.elapse(const Duration(seconds: 2));
        expect(container.read(ludoAnimationQueueProvider).blocking, isFalse);
        expect(container.read(ludoAnimationQueueProvider).busy, isFalse);
      });
    });

    test('clear() during a drain never lets the old loop end the new presentation early', () {
      fakeAsync((async) {
        final queue = container.read(ludoAnimationQueueProvider.notifier);
        final dice = LudoMotion.diceRoll;
        queue.enqueue(const LudoPresentationEvent(kind: LudoPresentationKind.dice, playerId: 'me', diceValue: 6));
        async.elapse(dice - const Duration(milliseconds: 60));
        queue.clear(); // e.g. a recovery snapshot arrived
        queue.enqueue(const LudoPresentationEvent(kind: LudoPresentationKind.turn, playerId: 'p2'));
        // The old dice loop wakes up now; the turn notice (120 ms) must still be showing.
        async.elapse(const Duration(milliseconds: 70));
        expect(container.read(ludoAnimationQueueProvider).current?.kind, LudoPresentationKind.turn);
        async.elapse(const Duration(milliseconds: 100));
        expect(container.read(ludoAnimationQueueProvider).busy, isFalse);
      });
    });
  });

  group('commands fail fast', () {
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

    LudoMatchViewState state() => container.read(ludoMatchControllerProvider);

    test('a disconnected tap is rejected at once with a clear message, never left pending', () async {
      socket.reply = (event, _) => event == 'ludo:roll' ? {'ok': false, 'code': 'SOCKET_DISCONNECTED'} : _joinAck();
      await container.read(ludoMatchControllerProvider.notifier).join('m1');
      expect(await container.read(ludoMatchControllerProvider.notifier).roll(), isFalse);
      expect(state().pendingCommandId, isNull);
      expect(state().error, contains('Reconnecting'));
    });

    test('a timed-out command resyncs from the server instead of guessing', () async {
      socket.reply = (event, _) => event == 'ludo:roll' ? {'ok': false, 'code': 'ACK_TIMEOUT'} : _joinAck();
      await container.read(ludoMatchControllerProvider.notifier).join('m1');
      socket.sent.clear();
      expect(await container.read(ludoMatchControllerProvider.notifier).roll(), isFalse);
      await flush();
      expect(socket.sent, ['ludo:roll', 'match:join', 'ludo:sync']); // one send, no blind retry
      expect(state().pendingCommandId, isNull);
    });
  });
}
