import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_event_reducer.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/match_presenter.dart';

Map<String, dynamic> _token(String id, String owner, String color, int progress) => {
      'id': id,
      'ownerId': owner,
      'color': color,
      'state': progress < 0 ? 'BASE' : 'ACTIVE',
      'progress': progress,
    };

LudoRuntimeSnapshot _snapshot({
  String phase = 'PLAYING',
  String turnPhase = 'WAITING_FOR_MOVE',
  String current = 'me',
  List<String> legal = const ['RED-1'],
}) =>
    LudoRuntimeSnapshot.fromJson({
      'game': {
        'matchId': 'm1',
        'version': 7,
        'phase': phase,
        'turnPhase': turnPhase,
        'currentPlayerId': current,
        'diceValue': 6,
        'legalTokenIds': legal,
        'players': [
          {
            'userId': 'me',
            'color': 'RED',
            'tokens': [_token('RED-1', 'me', 'RED', 3), _token('RED-2', 'me', 'RED', -1)],
          },
          {
            'userId': 'p2',
            'color': 'YELLOW',
            'tokens': [_token('YELLOW-1', 'p2', 'YELLOW', 10), _token('YELLOW-2', 'p2', 'YELLOW', -1)],
          },
        ],
      },
      'startingRoll': {'round': 1, 'candidatePlayerIds': [], 'rolls': {}},
      'resignedPlayerIds': [],
    });

RealtimeEvent _event(String name, Map<String, dynamic> data, {String? serverTime}) => RealtimeEvent(
      name: name,
      payload: {'matchId': 'm1', 'version': 8, 'data': data, if (serverTime != null) 'serverTime': serverTime},
    );

MatchPresenter _present(
  LudoRuntimeSnapshot snapshot, {
  bool connected = true,
  LudoAnimationState animation = const LudoAnimationState(),
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
      me: 'me',
      animation: animation,
      connected: connected,
    );

void main() {
  group('reduceLudoEvent', () {
    test('a capture sends the captured token back to its yard', () {
      final next = reduceLudoEvent(
        _snapshot(),
        _event('ludo:token_moved', {
          'move': {
            'playerId': 'me',
            'diceValue': 6,
            'tokenBefore': _token('RED-1', 'me', 'RED', 3),
            'tokenAfter': _token('RED-1', 'me', 'RED', 9),
            'capturedTokenIds': ['YELLOW-1'],
          },
        }),
        8,
      );
      expect(next.game.version, 8);
      expect(next.game.tokenById('RED-1')?.progress, 9);
      expect(next.game.tokenById('YELLOW-1')?.state, LudoTokenState.base);
      expect(next.game.diceValue, isNull);
      expect(next.game.legalTokenIds, isEmpty);
    });

    test('match finished freezes the board with the final order', () {
      final next = reduceLudoEvent(_snapshot(), _event('match:finished', {'winnerOrder': ['p2', 'me']}), 8);
      expect(next.game.phase, LudoMatchPhase.finished);
      expect(next.game.winnerOrder, ['p2', 'me']);
      expect(next.game.currentPlayerId, isNull);
    });

    test('a new turn estimates the deadline from server time', () {
      final snapshot = reduceLudoEvent(_snapshot(), _event('ludo:turn_started', {'playerId': 'p2'}), 8);
      final timing = estimateTimingAfterEvent(
        null,
        snapshot,
        _event('ludo:turn_started', {'playerId': 'p2'}, serverTime: '2026-01-01T10:00:00.000Z'),
        turnSeconds: 20,
      );
      expect(timing?.playerId, 'p2');
      expect(timing?.turnEndsAt, DateTime.parse('2026-01-01T10:00:20.000Z'));
      expect(timing?.estimated, isTrue);
    });
  });

  group('MatchPresenter', () {
    test('only my legal tokens are tappable, and only when input is open', () {
      List<String> ids(MatchPresenter view) => [
            for (final t in view.tokens(onMove: (_) {}))
              if (t.isSelectable) t.id,
          ];
      expect(ids(_present(_snapshot())), ['RED-1']);
      expect(ids(_present(_snapshot(), connected: false)), isEmpty);
      const rolling = LudoAnimationState(
        current: LudoPresentationEvent(kind: LudoPresentationKind.dice, playerId: 'me'),
        blocking: true,
      );
      expect(ids(_present(_snapshot(), animation: rolling)), isEmpty);
    });

    test('a short notice does not hold back my move', () {
      const notice = LudoAnimationState(current: LudoPresentationEvent(kind: LudoPresentationKind.turn, playerId: 'me'));
      expect(_present(_snapshot(), animation: notice).tokens(onMove: (_) {}).where((t) => t.isSelectable), hasLength(1));
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
        me: 'me',
        animation: const LudoAnimationState(),
        connected: true,
      );
      final ghost = view.ghosts(onMove: (_) {}).single;
      expect(ghost.toProgress, 9);
      expect(ghost.captures, isTrue);
    });
  });
}
