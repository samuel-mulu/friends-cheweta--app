class MatchParticipantSummary {
  const MatchParticipantSummary({required this.userId, required this.fullName, required this.seat, this.resultPosition});
  final String userId;
  final String fullName;
  final int seat;
  final int? resultPosition;

  factory MatchParticipantSummary.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map ? Map<String, dynamic>.from(json['user'] as Map) : const <String, dynamic>{};
    return MatchParticipantSummary(
      userId: json['userId']?.toString() ?? user['id']?.toString() ?? '',
      fullName: user['fullName']?.toString() ?? 'Player',
      seat: int.tryParse(json['seat']?.toString() ?? '') ?? 0,
      resultPosition: int.tryParse(json['resultPosition']?.toString() ?? ''),
    );
  }
}

class MatchSettlementSummary {
  const MatchSettlementSummary({required this.winnerUserId, required this.potAmountMinor, required this.platformFeeMinor, required this.payoutAmountMinor, this.settledAt});
  final String winnerUserId;
  final int potAmountMinor;
  final int platformFeeMinor;
  final int payoutAmountMinor;
  final DateTime? settledAt;

  factory MatchSettlementSummary.fromJson(Map<String, dynamic> json) => MatchSettlementSummary(
        winnerUserId: json['winnerUserId']?.toString() ?? '',
        potAmountMinor: int.tryParse(json['potAmountMinor']?.toString() ?? '') ?? 0,
        platformFeeMinor: int.tryParse(json['platformFeeMinor']?.toString() ?? '') ?? 0,
        payoutAmountMinor: int.tryParse(json['payoutAmountMinor']?.toString() ?? '') ?? 0,
        settledAt: DateTime.tryParse(json['settledAt']?.toString() ?? ''),
      );
}

class MatchHistoryItem {
  const MatchHistoryItem({
    required this.id,
    required this.status,
    required this.gameName,
    required this.modeName,
    required this.stakeAmountMinor,
    required this.participants,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.settlement,
    this.winnerOrder = const [],
    this.source,
    this.isDraw = false,
    this.gameCode,
  });

  final String id;

  /// CHALLENGE | REMATCH | INVITE | PRACTICE (free game vs computer).
  final String? source;
  bool get isPractice => source == 'PRACTICE';
  final String status;
  final String gameName;
  final String modeName;
  final int stakeAmountMinor;
  final List<MatchParticipantSummary> participants;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final MatchSettlementSummary? settlement;
  final List<String> winnerOrder;

  /// Finished without a winner (Dama draw rule); stakes were returned.
  final bool isDraw;

  /// LUDO | DAMA (from `game.code`).
  final String? gameCode;

  factory MatchHistoryItem.fromJson(Map<String, dynamic> json) {
    final game = json['game'] is Map ? Map<String, dynamic>.from(json['game'] as Map) : const <String, dynamic>{};
    final mode = json['gameMode'] is Map ? Map<String, dynamic>.from(json['gameMode'] as Map) : const <String, dynamic>{};
    final settlementJson = json['settlement'];
    return MatchHistoryItem(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'UNKNOWN',
      gameName: game['name']?.toString() ?? game['code']?.toString() ?? 'Game',
      modeName: mode['name']?.toString() ?? mode['code']?.toString() ?? '',
      stakeAmountMinor: int.tryParse(json['stakeAmountMinor']?.toString() ?? '') ?? 0,
      participants: (json['participants'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => MatchParticipantSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
      finishedAt: DateTime.tryParse(json['finishedAt']?.toString() ?? ''),
      settlement: settlementJson is Map ? MatchSettlementSummary.fromJson(Map<String, dynamic>.from(settlementJson)) : null,
      winnerOrder: (json['winnerOrder'] as List? ?? const []).map((e) => e.toString()).toList(),
      source: json['source']?.toString(),
      isDraw: json['isDraw'] == true,
      gameCode: game['code']?.toString(),
    );
  }

  MatchParticipantSummary? participant(String userId) {
    for (final p in participants) {
      if (p.userId == userId) return p;
    }
    return null;
  }
}

class MatchReplayEvent {
  const MatchReplayEvent({required this.id, required this.sequence, required this.version, required this.type, required this.createdAt, required this.payload});
  final String id;
  final int sequence;
  final int version;
  final String type;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  factory MatchReplayEvent.fromJson(Map<String, dynamic> json) => MatchReplayEvent(
        id: json['id']?.toString() ?? '',
        sequence: int.tryParse(json['sequence']?.toString() ?? '') ?? 0,
        version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
        type: json['type']?.toString() ?? 'EVENT',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload'] as Map) : const {},
      );
}

class MatchReplay {
  const MatchReplay({required this.match, required this.events});
  final MatchHistoryItem match;
  final List<MatchReplayEvent> events;

  factory MatchReplay.fromJson(Map<String, dynamic> json) => MatchReplay(
        match: MatchHistoryItem.fromJson(Map<String, dynamic>.from(json['match'] as Map)),
        events: (json['events'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => MatchReplayEvent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
