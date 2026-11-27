import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/ludo/application/ludo_event_reducer.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_timeline_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/match_presenter.dart';
import 'support/ludo_fixtures.dart';

/// Ludo types on the client: what the server decides, shown without hints
/// where the type says so (መመለስ የረሳ ይሸነፋል).
MatchPresenter _present(LudoRuntimeSnapshot snapshot) => MatchPresenter(
      match: LudoMatchViewState(
        matchId: 'm1',
        snapshot: snapshot,
        legalMoves: const [
          LudoMovePreview(tokenId: 'RED-1', toProgress: 9, captures: ['YELLOW-1'], safe: false),
        ],
        participants: const [
          LudoMatchParticipant(userId: 'me', fullName: 'Me Myself', seat: 0, color: LudoColor.red),
          LudoMatchParticipant(userId: 'p2', fullName: 'Samuel Mulu', seat: 1, color: LudoColor.yellow),
        ],
      ),
      timeline: LudoTimelineState(presented: snapshot),
      me: 'me',
      connected: true,
    );

LudoRuntimeSnapshot _myMove(String rulesVersion) =>
    snapshotWith(rulesVersion: rulesVersion, turnPhase: 'WAITING_FOR_MOVE', dice: 6, legal: const ['RED-1'], red: [3, -1], yellow: [9, -1]);

void main() {
  test('capture hints show in the classic type, never in "forget to send back and you lose"', () {
    expect(_present(_myMove('LUDO_CLASSIC_V3')).ghosts(onMove: (_) {}).single.captures, isTrue);
    expect(_present(_myMove('LUDO_MISSED_CAPTURE_V1')).ghosts(onMove: (_) {}).single.captures, isFalse);
  });

  test('a missed capture puts the player out and says why the match ended', () {
    final missed = reduceLudoEvent(
      _myMove('LUDO_MISSED_CAPTURE_V1'),
      ludoEvent('ludo:capture_missed', {'playerId': 'me', 'tokenId': 'RED-2', 'tokenIds': ['RED-1']}),
      8,
    );
    expect(missed.resignedPlayerIds, ['me']);
    expect(missed.missedCapturePlayerIds, ['me']);
    expect(missed.game.tokenById('RED-1')?.state, LudoTokenState.base);

    final finished = reduceLudoEvent(missed, ludoEvent('match:finished', {'winnerOrder': ['p2', 'me']}), 9);
    final view = _present(finished);
    expect(view.hint, contains('the match is lost'));
    expect(view.seats(onRoll: (_) {}, reactions: const {}).firstWhere((seat) => seat.isMe).status, 'Missed a capture');
  });

  test('the server snapshot carries who missed a capture (after a reconnect)', () {
    final json = {
      'game': {
        'rulesVersion': 'LUDO_MISSED_CAPTURE_V1',
        'matchId': 'm1',
        'phase': 'FINISHED',
        'turnPhase': 'COMPLETE',
        'players': const [],
      },
      'startingRoll': {'round': 1, 'candidatePlayerIds': const [], 'rolls': const {}},
      'resignedPlayerIds': ['p2'],
      'missedCapturePlayerIds': ['p2'],
    };
    final snapshot = LudoRuntimeSnapshot.fromJson(json);
    expect(snapshot.missedCapturePlayerIds, ['p2']);
    expect(snapshot.hidesCaptureHints, isTrue);
  });
}
