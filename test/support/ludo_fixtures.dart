import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_board_spec.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';

/// Test builders for Ludo snapshots and server events.

Map<String, dynamic> tokenJson(String id, String owner, String color, int progress, {LudoBoardSpec board = LudoBoardSpec.standard}) => {
      'id': id,
      'ownerId': owner,
      'color': color,
      'state': progress < 0
          ? 'BASE'
          : board.isFinished(progress)
              ? 'FINISHED'
              : board.isHome(progress)
                  ? 'HOME_PATH'
                  : 'ACTIVE',
      'progress': progress,
    };

/// RED = me, YELLOW = p2. [red]/[yellow] are token progresses (-1 = yard).
LudoRuntimeSnapshot snapshotWith({
  List<int> red = const [3, -1],
  List<int> yellow = const [10, -1],
  String phase = 'PLAYING',
  String turnPhase = 'WAITING_FOR_ROLL',
  String? current = 'me',
  int? dice,
  List<String> legal = const [],
  int version = 7,
  String rulesVersion = 'LUDO_CLASSIC_V3',
  int tokensToWin = 4,
}) {
  final board = LudoBoardSpec.fromRulesVersion(rulesVersion);
  return LudoRuntimeSnapshot.fromJson({
    'game': {
      'rulesVersion': rulesVersion,
      'matchId': 'm1',
      'version': version,
      'phase': phase,
      'turnPhase': turnPhase,
      'currentPlayerId': current,
      'diceValue': dice,
      'legalTokenIds': legal,
      'tokensToWin': tokensToWin,
      'players': [
        {
          'userId': 'me',
          'color': 'RED',
          'tokens': [for (final (i, p) in red.indexed) tokenJson('RED-${i + 1}', 'me', 'RED', p, board: board)],
        },
        {
          'userId': 'p2',
          'color': 'YELLOW',
          'tokens': [for (final (i, p) in yellow.indexed) tokenJson('YELLOW-${i + 1}', 'p2', 'YELLOW', p, board: board)],
        },
      ],
    },
    'startingRoll': {'round': 1, 'candidatePlayerIds': [], 'rolls': {}},
    'resignedPlayerIds': [],
  });
}

RealtimeEvent ludoEvent(String name, Map<String, dynamic> data, {int version = 8, String? serverTime, int? batchIndex, int? batchSize}) =>
    RealtimeEvent(
      name: name,
      payload: {
        'eventId': 'evt-$name-$version-${data.hashCode}',
        'matchId': 'm1',
        'version': version,
        if (serverTime != null) 'serverTime': serverTime,
        if (batchIndex != null) 'batchIndex': batchIndex,
        if (batchSize != null) 'batchSize': batchSize,
        'data': data,
      },
    );

RealtimeEvent diceEvent(String playerId, int value, {int version = 8}) =>
    ludoEvent('ludo:dice_rolled', {'type': 'DICE_ROLLED', 'playerId': playerId, 'diceValue': value}, version: version);

RealtimeEvent moveEvent({
  required String playerId,
  required String tokenId,
  required String color,
  required int from,
  required int to,
  int dice = 1,
  List<String> captured = const [],
  int version = 9,
  LudoBoardSpec board = LudoBoardSpec.standard,
}) =>
    ludoEvent(
      'ludo:token_moved',
      {
        'type': 'TOKEN_MOVED',
        'playerId': playerId,
        'tokenId': tokenId,
        'move': {
          'playerId': playerId,
          'diceValue': dice,
          'tokenBefore': tokenJson(tokenId, playerId, color, from, board: board),
          'tokenAfter': tokenJson(tokenId, playerId, color, to, board: board),
          'capturedTokenIds': captured,
          'move': {
            'tokenId': tokenId,
            'fromProgress': from,
            'toProgress': to,
            'path': from < 0 ? [-1, 0] : [for (var p = from; p <= to; p++) p],
          },
        },
      },
      version: version,
    );
