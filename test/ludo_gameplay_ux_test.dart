import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/features/ludo/application/ludo_feedback.dart';
import 'package:friends_game_app/features/ludo/application/ludo_scene.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_board_spec.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_dice.dart';
import 'support/ludo_fixtures.dart';

LudoToken _token(LudoColor color, int progress, {String owner = 'me'}) => LudoToken(
      id: '${color.name}-1',
      ownerId: owner,
      color: color,
      state: progress < 0
          ? LudoTokenState.base
          : progress >= 56
              ? LudoTokenState.finished
              : LudoTokenState.active,
      progress: progress,
    );

LudoMoveResolution _move(int from, int to, {LudoColor color = LudoColor.red, List<String> captured = const []}) =>
    LudoMoveResolution(
      playerId: 'me',
      diceValue: 6,
      tokenBefore: _token(color, from),
      tokenAfter: _token(color, to),
      capturedTokenIds: captured,
    );

LudoMoveScene _moveScene(int from, int to, {List<String> captured = const []}) => LudoMoveScene(
      moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: from, to: to, captured: captured),
      move: _move(from, to, captured: captured),
      includeCaptures: captured.isEmpty,
    );

void main() {
  group('board orientation', () {
    test('every viewer color ends up bottom-left', () {
      for (final color in LudoColor.values) {
        expect(LudoBoardOrientation.forViewer(color).cornerOf(color), LudoCorner.bottomLeft, reason: color.name);
      }
    });

    test('in a 2-player game the opponent sits in the opposite corner', () {
      final view = LudoBoardOrientation.forViewer(LudoColor.red);
      expect(view.cornerOf(LudoColor.yellow), LudoCorner.topRight);
    });

    test('point rotation agrees with corner mapping', () {
      const size = 100.0;
      final view = LudoBoardOrientation.forViewer(LudoColor.red); // red yard is painted top-left
      final rotated = view.rotate(const Offset(10, 10), size);
      expect(rotated.dx, lessThan(size / 2));
      expect(rotated.dy, greaterThan(size / 2)); // now bottom-left
    });
  });

  group('motion', () {
    test('leaving the yard is a single hop onto the start square', () {
      expect(LudoMotion.path(_move(-1, 0)), [-1, 0]);
    });

    test('a normal move visits every cell', () {
      expect(LudoMotion.path(_move(10, 14)), [10, 11, 12, 13, 14]);
      expect(LudoMotion.steps(_move(10, 14)), 4);
    });

    test('move presentation time scales with distance and matches the scene', () {
      expect(LudoMotion.moveDuration(_move(0, 6)), greaterThan(LudoMotion.moveDuration(_move(0, 1))));
      expect(_moveScene(0, 3).nominal, LudoMotion.moveDuration(_move(0, 3)));
    });

    test('catching up shortens durations but never below a frame', () {
      expect(LudoMotion.scaled(const Duration(milliseconds: 650), 2.5), const Duration(milliseconds: 260));
      expect(LudoMotion.scaled(const Duration(milliseconds: 10), 2.5), const Duration(microseconds: 16000));
      expect(LudoMotion.scaled(const Duration(milliseconds: 650), 1), const Duration(milliseconds: 650));
    });
  });

  group('feedback', () {
    const board = LudoBoardSpec.standard;

    test('opponent dice is quieter than mine; my tapped die does not click twice', () {
      final mine = LudoDiceScene(diceEvent('me', 4), value: 4, startRoll: false);
      final theirs = LudoDiceScene(diceEvent('other', 4), value: 4, startRoll: false);
      expect(sceneStartFeedback(mine, me: 'me').volume, 1.0);
      expect(sceneStartFeedback(mine, me: 'me').sound, GameSound.diceRoll);
      expect(sceneStartFeedback(mine, me: 'me', fromOptimisticTap: true).sound, isNull);
      expect(sceneStartFeedback(theirs, me: 'me').volume, lessThan(1.0));
    });

    test('a walk is silent when it starts: landing decides safe / capture / home', () {
      expect(sceneStartFeedback(_moveScene(5, 8), me: 'me').sound, isNull);
      // Red progress 8 = global square 8 (safe).
      expect(landingFeedback(_moveScene(5, 8), me: 'me', board: board, tokenOwners: const {}).sound, GameSound.safe);
      expect(landingFeedback(_moveScene(5, 7), me: 'me', board: board, tokenOwners: const {}).sound, isNull);
      expect(
        landingFeedback(_moveScene(5, 8, captured: ['YELLOW-1']), me: 'me', board: board, tokenOwners: const {}).sound,
        GameSound.capture,
      );
      expect(landingFeedback(_moveScene(55, 56), me: 'me', board: board, tokenOwners: const {}).sound, GameSound.home);
    });

    test('losing a token to a capture gives a strong haptic', () {
      final f = landingFeedback(
        LudoMoveScene(
          moveEvent(playerId: 'other', tokenId: 'YELLOW-1', color: 'YELLOW', from: 30, to: 35, captured: ['RED-2']),
          move: LudoMoveResolution(
            playerId: 'other',
            diceValue: 5,
            tokenBefore: _token(LudoColor.yellow, 30, owner: 'other'),
            tokenAfter: _token(LudoColor.yellow, 35, owner: 'other'),
            capturedTokenIds: const ['RED-2'],
          ),
          includeCaptures: false,
        ),
        me: 'me',
        board: board,
        tokenOwners: {'RED-2': 'me'},
      );
      expect(f.sound, GameSound.capture);
      expect(f.haptic, LudoHaptic.heavy);
    });

    test('my steps are a little louder than the opponent\'s', () {
      expect(stepFeedback(_moveScene(1, 2), me: 'me').volume, greaterThan(stepFeedback(_moveScene(1, 2), me: 'x').volume));
      expect(stepFeedback(_moveScene(1, 2), me: 'me').sound, GameSound.step);
    });

    test('"your turn" pings only when the board is quiet and it is my roll', () {
      final mine = snapshotWith().game;
      expect(shouldPingMyTurn(authoritative: mine, timelineIdle: true, me: 'me'), isTrue);
      expect(shouldPingMyTurn(authoritative: mine, timelineIdle: false, me: 'me'), isFalse);
      expect(shouldPingMyTurn(authoritative: snapshotWith(current: 'p2').game, timelineIdle: true, me: 'me'), isFalse);
      expect(shouldPingMyTurn(authoritative: snapshotWith(turnPhase: 'WAITING_FOR_MOVE').game, timelineIdle: true, me: 'me'), isFalse);
    });

    test('match end plays win or lose for the viewer', () {
      LudoFeedback end(List<String> winners) => sceneStartFeedback(
            LudoMatchEndScene(ludoEvent('match:finished', {'winnerOrder': winners}), winnerOrder: winners),
            me: 'me',
          );
      expect(end(['me', 'other']).sound, GameSound.win);
      expect(end(['other', 'me']).sound, GameSound.lose);
    });
  });

  group('dice', () {
    Widget host(int key, {bool spinning = false, VoidCallback? onSettled}) => MaterialApp(
          home: Scaffold(
            body: Center(child: LudoDice(value: 4, animateKey: key, spinning: spinning, onSettled: onSettled)),
          ),
        );

    bool isRolling(WidgetTester tester) => find.bySemanticsLabel('Dice rolling').evaluate().isNotEmpty;

    testWidgets('does not replay a roll when its key moves backwards (other player rolled)', (tester) async {
      await tester.pumpWidget(host(5));
      await tester.pumpWidget(host(0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(isRolling(tester), isFalse);
    });

    testWidgets('rolls when its own key increases, settles on the server face and reports it', (tester) async {
      var settled = 0;
      await tester.pumpWidget(host(1, onSettled: () => settled++));
      await tester.pumpWidget(host(2, onSettled: () => settled++));
      await tester.pump(const Duration(milliseconds: 50));
      expect(isRolling(tester), isTrue);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Dice result 4'), findsOneWidget);
      expect(settled, 1);
    });

    testWidgets('spins immediately on tap and stops cleanly if the roll is rejected', (tester) async {
      await tester.pumpWidget(host(1));
      await tester.pumpWidget(host(1, spinning: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(isRolling(tester), isTrue);
      await tester.pumpWidget(host(1));
      await tester.pump();
      expect(isRolling(tester), isFalse);
    });
  });
}
