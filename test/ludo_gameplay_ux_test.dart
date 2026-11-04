import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_feedback.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_dice.dart';

LudoToken _token(LudoColor color, int progress, {String owner = 'me'}) => LudoToken(
      id: '${color.name}-1',
      ownerId: owner,
      color: color,
      state: progress < 0 ? LudoTokenState.base : LudoTokenState.active,
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

    test('move presentation time scales with distance', () {
      expect(LudoMotion.moveDuration(_move(0, 6)), greaterThan(LudoMotion.moveDuration(_move(0, 1))));
      expect(
        LudoAnimationQueueController.durationFor(LudoPresentationEvent(kind: LudoPresentationKind.move, move: _move(0, 3))),
        LudoMotion.moveDuration(_move(0, 3)),
      );
    });
  });

  group('feedback', () {
    LudoFeedback fb(LudoPresentationEvent e, {List<String> winners = const [], Map<String, String> owners = const {}}) =>
        feedbackFor(e, me: 'me', winnerOrder: winners, tokenOwners: owners);

    test('opponent dice is quieter than mine', () {
      expect(fb(const LudoPresentationEvent(kind: LudoPresentationKind.dice, playerId: 'me')).volume, 1.0);
      expect(fb(const LudoPresentationEvent(kind: LudoPresentationKind.dice, playerId: 'other')).volume, lessThan(1.0));
    });

    test('landing on a safe square chimes; captures use the capture sound instead', () {
      // Red progress 8 = global square 8 (safe).
      expect(fb(LudoPresentationEvent(kind: LudoPresentationKind.move, move: _move(5, 8))).sound, GameSound.safe);
      expect(fb(LudoPresentationEvent(kind: LudoPresentationKind.move, move: _move(5, 7))).sound, isNull);
    });

    test('losing a token to a capture gives a strong haptic', () {
      final f = fb(
        const LudoPresentationEvent(kind: LudoPresentationKind.capture, playerId: 'other', tokenIds: ['RED-2']),
        owners: {'RED-2': 'me'},
      );
      expect(f.sound, GameSound.capture);
      expect(f.haptic, LudoHaptic.heavy);
    });

    test('only my turn pings', () {
      expect(fb(const LudoPresentationEvent(kind: LudoPresentationKind.turn, playerId: 'me')).sound, GameSound.yourTurn);
      expect(fb(const LudoPresentationEvent(kind: LudoPresentationKind.turn, playerId: 'other')).sound, isNull);
    });

    test('match end plays win or lose for the viewer', () {
      const end = LudoPresentationEvent(kind: LudoPresentationKind.matchFinished);
      expect(fb(end, winners: ['me', 'other']).sound, GameSound.win);
      expect(fb(end, winners: ['other', 'me']).sound, GameSound.lose);
    });
  });

  group('dice', () {
    Widget host(int key, {bool spinning = false}) => MaterialApp(
          home: Scaffold(body: Center(child: LudoDice(value: 4, animateKey: key, spinning: spinning))),
        );

    bool isRolling(WidgetTester tester) => find.bySemanticsLabel('Dice rolling').evaluate().isNotEmpty;

    testWidgets('does not replay a roll when its key moves backwards (other player rolled)', (tester) async {
      await tester.pumpWidget(host(5));
      await tester.pumpWidget(host(0));
      await tester.pump(const Duration(milliseconds: 50));
      expect(isRolling(tester), isFalse);
    });

    testWidgets('rolls when its own key increases and settles on the server face', (tester) async {
      await tester.pumpWidget(host(1));
      await tester.pumpWidget(host(2));
      await tester.pump(const Duration(milliseconds: 50));
      expect(isRolling(tester), isTrue);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Dice result 4'), findsOneWidget);
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
