import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/ludo/application/ludo_event_reducer.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_scene.dart';
import 'package:friends_game_app/features/ludo/application/ludo_timeline_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/match_presenter.dart';
import 'support/ludo_fixtures.dart';

LudoRuntimeSnapshot _snapshot({
  String phase = 'PLAYING',
  String turnPhase = 'WAITING_FOR_MOVE',
  String current = 'me',
  List<String> legal = const ['RED-1'],
}) =>
    snapshotWith(phase: phase, turnPhase: turnPhase, current: current, legal: legal, dice: 6, red: [3, -1], yellow: [10, -1]);

MatchPresenter _present(
  LudoRuntimeSnapshot snapshot, {
  bool connected = true,
  LudoTimelineState? timeline,
}) =>
    MatchPresenter(
      match: LudoMatchViewState(
        matchId: 'm1',
        snapshot: snapshot,
        participants: const [
          LudoMatchParticipant(userId: 'me', fullName: 'Me Myself', seat: 0, color: LudoColor.red),
          LudoMatchParticipant(userId: 'p2', fullName: 'Samuel Mulu', seat: 1, color: LudoColor.yellow),
        ],
      ),
      timeline: timeline ?? LudoTimelineState(presented: snapshot),
      me: 'me',
      connected: connected,
    );

void main() {
  group('reduceLudoEvent', () {
    test('a capture sends the captured token back to its yard', () {
      final next = reduceLudoEvent(
        _snapshot(),
        moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 3, to: 9, dice: 6, captured: ['YELLOW-1'], version: 8),
        8,
      );
      expect(next.game.version, 8);
      expect(next.game.tokenById('RED-1')?.progress, 9);
      expect(next.game.tokenById('YELLOW-1')?.state, LudoTokenState.base);
      expect(next.game.diceValue, isNull);
      expect(next.game.legalTokenIds, isEmpty);
    });

    test('presented steps: the mover lands first, the victim flies home later', () {
      final event = moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 3, to: 9, dice: 6, captured: ['YELLOW-1'], version: 8);
      final move = LudoMoveResolution.fromJson(Map<String, dynamic>.from(event.data['move'] as Map));
      final landed = applyMoveToPresented(_snapshot(), event, move, includeCaptures: false);
      expect(landed.game.tokenById('RED-1')?.progress, 9);
      expect(landed.game.tokenById('YELLOW-1')?.progress, 10, reason: 'still on the square');
      final flown = applyCapturesToPresented(landed, ['YELLOW-1']);
      expect(flown.game.tokenById('YELLOW-1')?.progress, -1);
    });

    test('match finished freezes the board with the final order', () {
      final next = reduceLudoEvent(_snapshot(), ludoEvent('match:finished', {'winnerOrder': ['p2', 'me']}), 8);
      expect(next.game.phase, LudoMatchPhase.finished);
      expect(next.game.winnerOrder, ['p2', 'me']);
      expect(next.game.currentPlayerId, isNull);
    });

    test('a new turn estimates the deadline from server time', () {
      final snapshot = reduceLudoEvent(_snapshot(), ludoEvent('ludo:turn_started', {'playerId': 'p2'}), 8);
      final timing = estimateTimingAfterEvent(
        null,
        snapshot,
        ludoEvent('ludo:turn_started', {'playerId': 'p2'}, serverTime: '2026-01-01T10:00:00.000Z'),
        turnSeconds: 20,
      );
      expect(timing?.playerId, 'p2');
      expect(timing?.turnEndsAt, DateTime.parse('2026-01-01T10:00:20.000Z'));
      expect(timing?.estimated, isTrue);
    });
  });

  group('MatchPresenter', () {
    List<String> ids(MatchPresenter view) => [
          for (final t in view.tokens(onMove: (_) {}))
            if (t.isSelectable) t.id,
        ];

    test('only my legal tokens are tappable, and only when input is open', () {
      expect(ids(_present(_snapshot())), ['RED-1']);
      expect(ids(_present(_snapshot(), connected: false)), isEmpty);
      final rolling = LudoTimelineState(
        presented: _snapshot(),
        current: LudoDiceScene(diceEvent('me', 6), value: 6, startRoll: false),
        sequence: 1,
      );
      expect(ids(_present(_snapshot(), timeline: rolling)), isEmpty);
    });

    test('input waits until the board has caught up with the server', () {
      final authoritative = _snapshot(); // version 7
      final behind = LudoTimelineState(presented: snapshotWith(version: 6, legal: const ['RED-1'], turnPhase: 'WAITING_FOR_MOVE'));
      expect(_present(authoritative, timeline: behind).canAct, isFalse);
      final catchingUp = LudoTimelineState(presented: authoritative, speedFactor: 2.5);
      expect(_present(authoritative, timeline: catchingUp).canAct, isFalse);
      expect(_present(authoritative, timeline: catchingUp).hint, 'Catching up…');
    });

    test('a short notice does not hold back my move', () {
      final notice = LudoTimelineState(
        presented: _snapshot(),
        current: LudoTurnScene(ludoEvent('ludo:turn_started', {'playerId': 'me'})),
        sequence: 1,
      );
      // A turn notice is on stage (not idle), so input still waits for it to pass…
      expect(_present(_snapshot(), timeline: notice).canAct, isFalse);
      // …but it is not "blocking": the hint and dice state do not treat it as an animation.
      expect(notice.blocking, isFalse);
    });

    test('banner and hint follow whose turn it is', () {
      final mine = _present(_snapshot());
      expect(mine.banner.text, 'YOUR TURN');
      expect(mine.banner.mine, isTrue);
      expect(mine.hint, 'Tap a glowing token to move');

      final theirs = _present(_snapshot(current: 'p2', turnPhase: 'WAITING_FOR_ROLL', legal: []));
      expect(theirs.banner.text, contains("'S TURN"));
      expect(theirs.hint, isEmpty);
    });

    test('notices and extra rolls take over the banner while they show', () {
      final snapshot = _snapshot(turnPhase: 'WAITING_FOR_ROLL', legal: []);
      final noMove = LudoTimelineState(
        presented: snapshot,
        current: LudoNoticeScene(ludoEvent('ludo:no_legal_move', {'playerId': 'me'}), kind: LudoNoticeKind.noLegalMove),
        sequence: 1,
      );
      expect(_present(snapshot, timeline: noMove).banner.text, 'NO MOVE FOR YOU');
      final extra = LudoTimelineState(
        presented: snapshot,
        current: LudoExtraRollScene(ludoEvent('ludo:extra_roll_granted', {'playerId': 'me'})),
        sequence: 1,
      );
      expect(_present(snapshot, timeline: extra).banner.text, 'EXTRA ROLL!');
    });

    test('a tap that cannot act always gets an explanation', () {
      expect(_present(_snapshot(current: 'p2', legal: [])).tapExplanation, 'Wait for your turn');
      expect(_present(_snapshot(turnPhase: 'WAITING_FOR_ROLL', legal: [])).tapExplanation, 'Roll your dice first');
      expect(_present(_snapshot()).tapExplanation, 'Tap a glowing token');
      expect(_present(_snapshot(), connected: false).tapExplanation, 'Reconnecting…');
    });

    test('landing previews only while it is my move', () {
      final view = MatchPresenter(
        match: LudoMatchViewState(
          matchId: 'm1',
          snapshot: _snapshot(),
          participants: const [LudoMatchParticipant(userId: 'me', fullName: 'Me', seat: 0, color: LudoColor.red)],
          legalMoves: const [LudoMovePreview(tokenId: 'RED-1', toProgress: 9, captures: ['YELLOW-1'], safe: false)],
        ),
        timeline: LudoTimelineState(presented: _snapshot()),
        me: 'me',
        connected: true,
      );
      final ghost = view.ghosts(onMove: (_) {}).single;
      expect(ghost.toProgress, 9);
      expect(ghost.captures, isTrue);
    });

    test('the board draws the presented snapshot, not the authoritative one', () {
      final authoritative = snapshotWith(red: [9, -1], version: 9);
      final presented = snapshotWith(red: [3, -1], version: 8);
      final view = _present(authoritative, timeline: LudoTimelineState(presented: presented));
      expect(view.tokens(onMove: (_) {}).firstWhere((t) => t.id == 'RED-1').progress, 3);
      expect(view.canAct, isFalse);
    });
  });
}
