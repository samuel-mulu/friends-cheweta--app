import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_timeline_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_token.dart';
import 'support/fake_socket.dart';
import 'support/ludo_fixtures.dart';

Map<String, dynamic> _joinAck({int version = 5}) => {
      'ok': true,
      'state': {
        'game': {
          'rulesVersion': 'LUDO_CLASSIC_V3',
          'matchId': 'm1',
          'version': version,
          'phase': 'PLAYING',
          'turnPhase': 'WAITING_FOR_ROLL',
          'currentPlayerId': 'me',
          'legalTokenIds': [],
          'players': [
            {
              'userId': 'me',
              'color': 'RED',
              'tokens': [tokenJson('RED-1', 'me', 'RED', 3), tokenJson('RED-2', 'me', 'RED', -1)],
            },
          ],
        },
        'startingRoll': {'round': 1, 'candidatePlayerIds': [], 'rolls': {}},
        'resignedPlayerIds': [],
      },
      'timing': {'matchId': 'm1', 'version': version, 'turnPhase': 'WAITING_FOR_ROLL', 'consecutiveTimeoutsByPlayer': {}},
      'participants': [],
      'board': {'trackLength': 52, 'lapSquares': 51, 'homeColumnLength': 5},
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
    LudoTimelineState timeline() => container.read(ludoTimelineProvider);

    test('a disconnected tap is rejected at once with a clear message, never left pending', () async {
      socket.reply = (event, _) => event == 'ludo:roll' ? {'ok': false, 'code': 'SOCKET_DISCONNECTED'} : _joinAck();
      await container.read(ludoMatchControllerProvider.notifier).join('m1');
      expect(await container.read(ludoMatchControllerProvider.notifier).roll(), isFalse);
      expect(state().pendingCommandId, isNull);
      expect(state().error, contains('Reconnecting'));
      expect(timeline().spinningPlayerId, isNull, reason: 'a rejected roll stops the optimistic spin');
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

    test('joining seeds the timeline with the server board, and events flow through it', () async {
      socket.reply = (_, __) => _joinAck();
      await container.read(ludoMatchControllerProvider.notifier).join('m1');
      expect(timeline().presented?.game.version, 5);
      expect(timeline().presented?.board.lapSquares, 51);

      socket.push('ludo:dice_rolled', {'type': 'DICE_ROLLED', 'playerId': 'me', 'diceValue': 6}, matchId: 'm1', version: 6);
      await flush();
      // Authoritative state moved on; the board shows the dice scene first.
      expect(state().snapshot?.game.diceValue, 6);
      expect(timeline().busy, isTrue);
      expect(timeline().presentedDice['me'], 6);
    });

    test('recovery replaces the board as is and drops stale scenes', () async {
      socket.reply = (event, _) => event == 'ludo:sync' ? _joinAck(version: 9) : _joinAck();
      await container.read(ludoMatchControllerProvider.notifier).join('m1');
      socket.push('ludo:dice_rolled', {'type': 'DICE_ROLLED', 'playerId': 'me', 'diceValue': 6}, matchId: 'm1', version: 6);
      await flush();
      expect(timeline().busy, isTrue);

      await container.read(ludoMatchControllerProvider.notifier).recover();
      expect(timeline().busy, isFalse);
      expect(timeline().presented?.game.version, 9);
      expect(state().snapshot?.game.version, 9);
    });

    test('a malformed event does not kill the stream: it triggers a resync', () async {
      socket.reply = (_, __) => _joinAck();
      await container.read(ludoMatchControllerProvider.notifier).join('m1');
      socket.sent.clear();
      socket.push(
        'ludo:token_moved',
        {
          'type': 'TOKEN_MOVED',
          'playerId': 'me',
          'move': {'playerId': 'me', 'diceValue': 1, 'tokenBefore': {'color': 'PURPLE'}, 'tokenAfter': {'color': 'PURPLE'}},
        },
        matchId: 'm1',
        version: 6,
      );
      await flush();
      await flush();
      expect(socket.sent, ['match:join', 'ludo:sync']);
      // Still alive afterwards.
      socket.push('ludo:dice_rolled', {'type': 'DICE_ROLLED', 'playerId': 'me', 'diceValue': 2}, matchId: 'm1', version: 6);
      await flush();
      expect(state().snapshot?.game.diceValue, 2);
    });
  });
}
