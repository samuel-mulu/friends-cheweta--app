import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/ludo/application/ludo_scene.dart';
import 'package:friends_game_app/features/ludo/application/ludo_timeline_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'support/ludo_fixtures.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  LudoTimelineController timeline() => container.read(ludoTimelineProvider.notifier);
  LudoTimelineState state() => container.read(ludoTimelineProvider);
  int progressOf(String id) => state().presented!.game.tokenById(id)!.progress;

  group('roll + auto-move + capture in one batch', () {
    // RED-1 at 3 walks to 9 and captures YELLOW-1 (yellow 35 = global 9).
    void feedBatch() {
      timeline().enqueue(diceEvent('me', 6, version: 8));
      timeline().enqueue(moveEvent(
        playerId: 'me',
        tokenId: 'RED-1',
        color: 'RED',
        from: 3,
        to: 9,
        dice: 6,
        captured: ['YELLOW-1'],
        version: 9,
      ));
    }

    test('the board never shows a token where it has not walked yet', () {
      fakeAsync((async) {
        timeline().seed(snapshotWith(red: [3, -1], yellow: [35, -1]));
        feedBatch();

        // Dice is on stage: nothing has moved.
        expect(state().current, isA<LudoDiceScene>());
        expect(state().presentedDice['me'], 6);
        expect(progressOf('RED-1'), 3);
        expect(progressOf('YELLOW-1'), 35);
        expect(state().blocking, isTrue);

        // The die lands → the walk begins; the mover still sits on its old square.
        timeline().completeScene(state().sequence);
        expect(state().current, isA<LudoMoveScene>());
        expect(progressOf('RED-1'), 3);
        expect(progressOf('YELLOW-1'), 35);

        // The walk ends → the mover lands, the victim stays on the square until it flies.
        timeline().completeScene(state().sequence);
        expect(state().current, isA<LudoCaptureScene>());
        expect(progressOf('RED-1'), 9);
        expect(progressOf('YELLOW-1'), 35);

        // The flight lands → yard. Presented now equals the server's state.
        timeline().completeScene(state().sequence);
        expect(state().idle, isTrue);
        expect(progressOf('YELLOW-1'), -1);
        expect(state().presented!.game.version, 9);
        expect(state().blocking, isFalse);
      });
    });

    test('stale completions are ignored', () {
      fakeAsync((async) {
        timeline().seed(snapshotWith(red: [3, -1], yellow: [35, -1]));
        feedBatch();
        final diceSeq = state().sequence;
        timeline().completeScene(diceSeq);
        timeline().completeScene(diceSeq); // late duplicate from the die widget
        expect(state().current, isA<LudoMoveScene>());
      });
    });
  });

  test('a widget that never reports is finished by the safety timer', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith());
      timeline().enqueue(diceEvent('me', 4));
      expect(state().busy, isTrue);
      async.elapse(LudoMotion.diceRoll * 2 + const Duration(milliseconds: 301));
      expect(state().idle, isTrue);
      expect(state().presentedDice['me'], 4);
    });
  });

  test('state-only events apply at once, in order, without stage time', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith(turnPhase: 'WAITING_FOR_MOVE', dice: 3));
      timeline().enqueue(ludoEvent('ludo:legal_moves_ready', {'playerId': 'me', 'tokenIds': ['RED-1']}, version: 8));
      expect(state().idle, isTrue);
      expect(state().presented!.game.legalTokenIds, ['RED-1']);
      expect(state().presented!.game.version, 8);
    });
  });

  test('a backlog plays fast and never skips a walk', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith(red: [0, -1]));
      for (var i = 0; i < 4; i++) {
        timeline().enqueue(moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: i * 6, to: (i + 1) * 6, dice: 6, version: 8 + i));
      }
      expect(state().isCatchingUp, isTrue);
      expect(state().speedFactor, LudoTimelineController.fastForwardFactor);
      expect(state().scale(LudoMotion.moveDuration(null)), lessThan(LudoMotion.moveDuration(null)));

      var walks = 0;
      while (state().current != null) {
        expect(state().current, isA<LudoMoveScene>());
        walks++;
        timeline().completeScene(state().sequence);
      }
      expect(walks, 4);
      expect(progressOf('RED-1'), 24);
      expect(state().isCatchingUp, isFalse);
      expect(state().speedFactor, 1.0);
    });
  });

  test('a short burst keeps normal speed', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith());
      timeline().enqueue(diceEvent('me', 2));
      timeline().enqueue(moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 3, to: 5, dice: 2));
      expect(state().isCatchingUp, isFalse);
    });
  });

  test('seed() drops everything mid-scene and shows the new snapshot as is', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith());
      timeline().enqueue(diceEvent('me', 6));
      timeline().enqueue(moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 3, to: 9, dice: 6));
      final before = state().epoch;

      final recovered = snapshotWith(red: [20, -1], version: 12);
      timeline().seed(recovered);
      expect(state().current, isNull);
      expect(state().pendingCount, 0);
      expect(state().epoch, before + 1);
      expect(progressOf('RED-1'), 20);

      // The old safety timer must not resurrect anything.
      async.elapse(const Duration(seconds: 5));
      expect(state().idle, isTrue);
      expect(progressOf('RED-1'), 20);
    });
  });

  test('my tapped die spins at once and its scene knows the sound already played', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith());
      timeline().startOptimisticSpin('me');
      expect(state().spinningPlayerId, 'me');

      timeline().enqueue(diceEvent('me', 5));
      expect(state().spinningPlayerId, isNull);
      expect(state().currentFromOptimisticTap, isTrue);
      expect(state().diceKeys['me'], state().sequence);
      expect(state().rollHistory['me'], [5]);
    });
  });

  test('an optimistic spin is capped if the server never answers', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith());
      timeline().startOptimisticSpin('me');
      async.elapse(LudoTimelineController.optimisticSpinCap + const Duration(milliseconds: 1));
      expect(state().spinningPlayerId, isNull);
    });
  });

  test('an opponent\'s roll is not marked as my tap', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith(current: 'p2'));
      timeline().startOptimisticSpin('me');
      timeline().enqueue(diceEvent('p2', 3));
      expect(state().currentFromOptimisticTap, isFalse);
      expect(state().spinningPlayerId, 'me');
    });
  });

  test('a move home adds a finish scene after the walk', () {
    fakeAsync((async) {
      timeline().seed(snapshotWith(red: [55, -1]));
      timeline().enqueue(moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 55, to: 56, dice: 1));
      expect(state().current, isA<LudoMoveScene>());
      timeline().completeScene(state().sequence);
      expect(state().current, isA<LudoFinishScene>());
      expect(state().presented!.game.tokenById('RED-1')!.state, LudoTokenState.finished);
      async.elapse(const Duration(milliseconds: 500));
      expect(state().idle, isTrue);
    });
  });

  test('token_captured / token_finished add nothing: the move already carries them', () {
    expect(scenesForEvent(ludoEvent('ludo:token_captured', {'tokenIds': ['YELLOW-1']})), isEmpty);
    expect(scenesForEvent(ludoEvent('ludo:token_finished', {'tokenId': 'RED-1'})), isEmpty);
    expect(scenesForEvent(ludoEvent('ludo:no_legal_move', {'playerId': 'me'})).single, isA<LudoNoticeScene>());
    expect(scenesForEvent(ludoEvent('ludo:third_six_forfeited', {'playerId': 'me'})).single, isA<LudoNoticeScene>());
  });
}
