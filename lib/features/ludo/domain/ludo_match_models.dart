import 'package:friends_game_app/features/ludo/domain/ludo_board_spec.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

enum LudoTokenState { base, active, homePath, finished }
enum LudoMatchPhase { preGame, playing, finished }
enum LudoTurnPhase { startRoll, waitingForRoll, waitingForMove, complete }

LudoColor _color(Object? raw) => switch (raw?.toString()) {
      'RED' => LudoColor.red,
      'GREEN' => LudoColor.green,
      'YELLOW' => LudoColor.yellow,
      'BLUE' => LudoColor.blue,
      _ => throw FormatException('Unknown Ludo color: $raw'),
    };

LudoTokenState _tokenState(Object? raw) => switch (raw?.toString()) {
      'BASE' => LudoTokenState.base,
      'ACTIVE' => LudoTokenState.active,
      'HOME_PATH' => LudoTokenState.homePath,
      'FINISHED' => LudoTokenState.finished,
      _ => throw FormatException('Unknown token state: $raw'),
    };

LudoMatchPhase _matchPhase(Object? raw) => switch (raw?.toString()) {
      'PRE_GAME' => LudoMatchPhase.preGame,
      'PLAYING' => LudoMatchPhase.playing,
      'FINISHED' => LudoMatchPhase.finished,
      _ => throw FormatException('Unknown match phase: $raw'),
    };

LudoTurnPhase _turnPhase(Object? raw) => switch (raw?.toString()) {
      'START_ROLL' => LudoTurnPhase.startRoll,
      'WAITING_FOR_ROLL' => LudoTurnPhase.waitingForRoll,
      'WAITING_FOR_MOVE' => LudoTurnPhase.waitingForMove,
      'COMPLETE' => LudoTurnPhase.complete,
      _ => throw FormatException('Unknown turn phase: $raw'),
    };

String turnPhaseWire(LudoTurnPhase phase) => switch (phase) {
      LudoTurnPhase.startRoll => 'START_ROLL',
      LudoTurnPhase.waitingForRoll => 'WAITING_FOR_ROLL',
      LudoTurnPhase.waitingForMove => 'WAITING_FOR_MOVE',
      LudoTurnPhase.complete => 'COMPLETE',
    };

class LudoToken {
  const LudoToken({required this.id, required this.ownerId, required this.color, required this.state, required this.progress});
  final String id;
  final String ownerId;
  final LudoColor color;
  final LudoTokenState state;
  final int progress;

  factory LudoToken.fromJson(Map<String, dynamic> json) => LudoToken(
        id: json['id']?.toString() ?? '',
        ownerId: json['ownerId']?.toString() ?? '',
        color: _color(json['color']),
        state: _tokenState(json['state']),
        progress: int.tryParse(json['progress']?.toString() ?? '') ?? -1,
      );

  LudoToken copyWith({LudoTokenState? state, int? progress}) => LudoToken(
        id: id,
        ownerId: ownerId,
        color: color,
        state: state ?? this.state,
        progress: progress ?? this.progress,
      );
}

class LudoPlayerState {
  const LudoPlayerState({required this.userId, required this.color, required this.tokens});
  final String userId;
  final LudoColor color;
  final List<LudoToken> tokens;

  factory LudoPlayerState.fromJson(Map<String, dynamic> json) => LudoPlayerState(
        userId: json['userId']?.toString() ?? '',
        color: _color(json['color']),
        tokens: (json['tokens'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => LudoToken.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
      );

  LudoPlayerState copyWith({List<LudoToken>? tokens}) => LudoPlayerState(userId: userId, color: color, tokens: tokens ?? this.tokens);
}

class LudoMatchParticipant {
  const LudoMatchParticipant({
    required this.userId,
    required this.fullName,
    required this.seat,
    required this.color,
  });

  final String userId;
  final String fullName;
  final int seat;
  final LudoColor? color;

  factory LudoMatchParticipant.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : const <String, dynamic>{};
    final rawColor = json['color']?.toString();
    return LudoMatchParticipant(
      userId: json['userId']?.toString() ?? user['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? user['fullName']?.toString() ?? 'Player',
      seat: int.tryParse(json['seat']?.toString() ?? '') ?? 0,
      color: rawColor == null || rawColor.isEmpty ? null : _color(rawColor),
    );
  }

  String displayLabel({String? myUserId}) {
    if (myUserId != null && myUserId == userId) return 'You';
    return _shortName(fullName);
  }

  String roleLabel({String? myUserId}) {
    if (myUserId != null && myUserId == userId) return 'You';
    return 'Opponent';
  }

  static String _shortName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Player';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first;
    return parts.first;
  }
}

class LudoGameState {
  const LudoGameState({
    required this.rulesVersion,
    required this.matchId,
    required this.version,
    required this.phase,
    required this.turnPhase,
    required this.players,
    required this.currentPlayerId,
    required this.diceValue,
    required this.consecutiveSixes,
    required this.legalTokenIds,
    required this.winnerOrder,
    this.tokensToWin = 4,
  });

  final String rulesVersion;
  final String matchId;
  final int version;
  final LudoMatchPhase phase;
  final LudoTurnPhase turnPhase;
  final List<LudoPlayerState> players;
  final String? currentPlayerId;
  final int? diceValue;
  final int consecutiveSixes;
  final List<String> legalTokenIds;
  final List<String> winnerOrder;

  /// "First to N home" (1-4); 4 = classic.
  final int tokensToWin;

  /// Tokens [userId] has brought home so far.
  int tokensHome(String userId) =>
      players.where((p) => p.userId == userId).expand((p) => p.tokens).where((t) => t.state == LudoTokenState.finished).length;

  factory LudoGameState.fromJson(Map<String, dynamic> json) => LudoGameState(
        rulesVersion: json['rulesVersion']?.toString() ?? '',
        matchId: json['matchId']?.toString() ?? '',
        version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
        phase: _matchPhase(json['phase']),
        turnPhase: _turnPhase(json['turnPhase']),
        players: (json['players'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => LudoPlayerState.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false),
        currentPlayerId: json['currentPlayerId']?.toString(),
        diceValue: int.tryParse(json['diceValue']?.toString() ?? ''),
        consecutiveSixes: int.tryParse(json['consecutiveSixes']?.toString() ?? '') ?? 0,
        legalTokenIds: (json['legalTokenIds'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
        winnerOrder: (json['winnerOrder'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
        tokensToWin: (int.tryParse(json['tokensToWin']?.toString() ?? '') ?? 4).clamp(1, 4).toInt(),
      );

  LudoGameState copyWith({
    int? version,
    LudoMatchPhase? phase,
    LudoTurnPhase? turnPhase,
    List<LudoPlayerState>? players,
    String? currentPlayerId,
    bool clearCurrentPlayer = false,
    int? diceValue,
    bool clearDiceValue = false,
    int? consecutiveSixes,
    List<String>? legalTokenIds,
    List<String>? winnerOrder,
  }) =>
      LudoGameState(
        rulesVersion: rulesVersion,
        matchId: matchId,
        version: version ?? this.version,
        phase: phase ?? this.phase,
        turnPhase: turnPhase ?? this.turnPhase,
        players: players ?? this.players,
        currentPlayerId: clearCurrentPlayer ? null : currentPlayerId ?? this.currentPlayerId,
        diceValue: clearDiceValue ? null : diceValue ?? this.diceValue,
        consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
        legalTokenIds: legalTokenIds ?? this.legalTokenIds,
        winnerOrder: winnerOrder ?? this.winnerOrder,
        tokensToWin: tokensToWin,
      );

  LudoToken? tokenById(String id) {
    for (final player in players) {
      for (final token in player.tokens) {
        if (token.id == id) return token;
      }
    }
    return null;
  }

  LudoGameState replaceToken(LudoToken replacement) {
    return copyWith(
      players: [
        for (final player in players)
          player.copyWith(tokens: [for (final token in player.tokens) token.id == replacement.id ? replacement : token]),
      ],
    );
  }
}

class LudoStartingRollState {
  const LudoStartingRollState({required this.round, required this.candidatePlayerIds, required this.rolls});
  final int round;
  final List<String> candidatePlayerIds;
  final Map<String, int> rolls;

  factory LudoStartingRollState.fromJson(Map<String, dynamic> json) => LudoStartingRollState(
        round: int.tryParse(json['round']?.toString() ?? '') ?? 1,
        candidatePlayerIds: (json['candidatePlayerIds'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
        rolls: (json['rolls'] is Map)
            ? Map<String, dynamic>.from(json['rolls'] as Map).map((key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0))
            : const {},
      );

  LudoStartingRollState copyWith({int? round, List<String>? candidatePlayerIds, Map<String, int>? rolls}) => LudoStartingRollState(
        round: round ?? this.round,
        candidatePlayerIds: candidatePlayerIds ?? this.candidatePlayerIds,
        rolls: rolls ?? this.rolls,
      );
}

class LudoRuntimeSnapshot {
  LudoRuntimeSnapshot({
    required this.game,
    required this.startingRoll,
    required this.resignedPlayerIds,
    LudoBoardSpec? board,
  }) : board = board ?? LudoBoardSpec.fromRulesVersion(game.rulesVersion);

  final LudoGameState game;
  final LudoStartingRollState startingRoll;
  final List<String> resignedPlayerIds;

  /// Progress thresholds for this match (server-sent, else from the rules version).
  final LudoBoardSpec board;

  factory LudoRuntimeSnapshot.fromJson(Map<String, dynamic> json, {LudoBoardSpec? board}) => LudoRuntimeSnapshot(
        game: LudoGameState.fromJson(Map<String, dynamic>.from(json['game'] as Map)),
        startingRoll: LudoStartingRollState.fromJson(Map<String, dynamic>.from(json['startingRoll'] as Map)),
        resignedPlayerIds: (json['resignedPlayerIds'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
        board: board,
      );

  LudoRuntimeSnapshot copyWith({LudoGameState? game, LudoStartingRollState? startingRoll, List<String>? resignedPlayerIds}) =>
      LudoRuntimeSnapshot(
        game: game ?? this.game,
        startingRoll: startingRoll ?? this.startingRoll,
        resignedPlayerIds: resignedPlayerIds ?? this.resignedPlayerIds,
        board: board,
      );
}

class LudoTimingState {
  const LudoTimingState({
    required this.matchId,
    required this.version,
    required this.playerId,
    required this.turnPhase,
    required this.turnEndsAt,
    required this.consecutiveTimeoutsByPlayer,
    this.estimated = false,
  });

  final String matchId;
  final int version;
  final String? playerId;
  final LudoTurnPhase turnPhase;
  final DateTime? turnEndsAt;
  final Map<String, int> consecutiveTimeoutsByPlayer;
  final bool estimated;

  factory LudoTimingState.fromJson(Map<String, dynamic> json) => LudoTimingState(
        matchId: json['matchId']?.toString() ?? '',
        version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
        playerId: json['playerId']?.toString(),
        turnPhase: _turnPhase(json['turnPhase']),
        turnEndsAt: DateTime.tryParse(json['turnEndsAt']?.toString() ?? ''),
        consecutiveTimeoutsByPlayer: (json['consecutiveTimeoutsByPlayer'] is Map)
            ? Map<String, dynamic>.from(json['consecutiveTimeoutsByPlayer'] as Map)
                .map((key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0))
            : const {},
      );

  LudoTimingState copyWith({
    int? version,
    String? playerId,
    bool clearPlayer = false,
    LudoTurnPhase? turnPhase,
    DateTime? turnEndsAt,
    bool clearDeadline = false,
    Map<String, int>? consecutiveTimeoutsByPlayer,
    bool? estimated,
  }) =>
      LudoTimingState(
        matchId: matchId,
        version: version ?? this.version,
        playerId: clearPlayer ? null : playerId ?? this.playerId,
        turnPhase: turnPhase ?? this.turnPhase,
        turnEndsAt: clearDeadline ? null : turnEndsAt ?? this.turnEndsAt,
        consecutiveTimeoutsByPlayer: consecutiveTimeoutsByPlayer ?? this.consecutiveTimeoutsByPlayer,
        estimated: estimated ?? this.estimated,
      );
}

class LudoMoveResolution {
  const LudoMoveResolution({
    required this.playerId,
    required this.diceValue,
    required this.tokenBefore,
    required this.tokenAfter,
    required this.capturedTokenIds,
    this.path = const [],
  });
  final String playerId;
  final int diceValue;
  final LudoToken tokenBefore;
  final LudoToken tokenAfter;
  final List<String> capturedTokenIds;

  /// Server-computed squares the token visits (including its start); empty
  /// from older servers, in which case the client derives it.
  final List<int> path;

  String get tokenId => tokenAfter.id;
  bool get captures => capturedTokenIds.isNotEmpty;
  bool get finishes => tokenAfter.state == LudoTokenState.finished;

  factory LudoMoveResolution.fromJson(Map<String, dynamic> json) {
    final nested = json['move'];
    final serverPath = (nested is Map ? nested['path'] : json['path']) as List?;
    return LudoMoveResolution(
      playerId: json['playerId']?.toString() ?? '',
      diceValue: int.tryParse(json['diceValue']?.toString() ?? '') ?? 0,
      tokenBefore: LudoToken.fromJson(Map<String, dynamic>.from(json['tokenBefore'] as Map)),
      tokenAfter: LudoToken.fromJson(Map<String, dynamic>.from(json['tokenAfter'] as Map)),
      capturedTokenIds: (json['capturedTokenIds'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
      path: serverPath == null
          ? const []
          : serverPath.map((e) => int.tryParse(e.toString())).whereType<int>().toList(growable: false),
    );
  }
}

/// Server-computed landing preview for one legal token (rules stay server-side).
class LudoMovePreview {
  const LudoMovePreview({required this.tokenId, required this.toProgress, required this.captures, required this.safe});

  final String tokenId;
  final int toProgress;
  final List<String> captures;
  final bool safe;

  static List<LudoMovePreview> listFrom(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((item) => LudoMovePreview(
                tokenId: item['tokenId']?.toString() ?? '',
                toProgress: int.tryParse(item['toProgress']?.toString() ?? '') ?? 0,
                captures: (item['captures'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
                safe: item['safe'] == true,
              ))
          .toList(growable: false)
      : const [];
}

/// "The server played for X" notice (turn timer ran out).
class LudoAutoPlayNotice {
  const LudoAutoPlayNotice({required this.playerId, required this.strikes, required this.maxStrikes, required this.seq});
  final String playerId;
  final int strikes;
  final int maxStrikes;

  /// Distinguishes two identical notices in a row.
  final int seq;
}
