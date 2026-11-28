/// ካርታ ላጥ ላጥ — Karta Lat Lat, as sent by the server (KARTA_LATLAT_V1).
///
/// The server shuffles, deals and decides; the deck order never reaches the
/// phone. Each round's SHA-256 commitment arrives before the call and the
/// seed after the round, so the app can verify the deal was fixed in advance.
library;

const kartaRanks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

enum KartaSuit {
  spades('S', '♠', false),
  hearts('H', '♥', true),
  diamonds('D', '♦', true),
  clubs('C', '♣', false);

  const KartaSuit(this.code, this.symbol, this.red);
  final String code;
  final String symbol;
  final bool red;

  static KartaSuit parse(String code) => values.firstWhere((s) => s.code == code, orElse: () => KartaSuit.spades);
}

/// A card like `10H`: rank then suit.
class KartaCard {
  const KartaCard(this.rank, this.suit);
  final String rank;
  final KartaSuit suit;

  factory KartaCard.parse(String code) => KartaCard(code.substring(0, code.length - 1), KartaSuit.parse(code.substring(code.length - 1)));

  String get label => '$rank${suit.symbol}';

  @override
  bool operator ==(Object other) => other is KartaCard && other.rank == rank && other.suit == suit;
  @override
  int get hashCode => Object.hash(rank, suit);
}

class KartaDealt {
  const KartaDealt(this.card, this.playerId);
  final KartaCard card;
  final String playerId;

  static List<KartaDealt> listFrom(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((d) => KartaDealt(KartaCard.parse(d['card']?.toString() ?? 'AS'), d['playerId']?.toString() ?? ''))
          .toList()
      : const [];
}

class KartaRoundResult {
  const KartaRoundResult({
    required this.round,
    required this.winnerId,
    required this.rank,
    required this.card,
    required this.flips,
    required this.seed,
  });
  final int round;
  final String winnerId;
  final String rank;
  final KartaCard card;
  final int flips;
  final String seed;

  static KartaRoundResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return KartaRoundResult(
      round: _int(raw['round']),
      winnerId: raw['winnerId']?.toString() ?? '',
      rank: raw['rank']?.toString() ?? '',
      card: KartaCard.parse(raw['card']?.toString() ?? 'AS'),
      flips: _int(raw['flips']),
      seed: raw['seed']?.toString() ?? '',
    );
  }
}

class KartaGame {
  const KartaGame({
    required this.matchId,
    required this.version,
    required this.finished,
    required this.playerIds,
    required this.targetScore,
    required this.scores,
    required this.round,
    required this.starterId,
    required this.callerId,
    required this.calling,
    required this.deckCommitment,
    this.calledRank,
    this.currentPlayerId,
    this.receiverId,
    this.dealt = const [],
    this.lastRound,
    this.winnerOrder = const [],
    this.finishReason,
    this.rulesVersion = 'KARTA_LATLAT_V1',
  });

  final String matchId;

  /// KARTA_LATLAT_V1 (1v1) or KARTA_TABLE_V1 (one round of a queue table).
  final String rulesVersion;
  bool get isTableRound => rulesVersion == 'KARTA_TABLE_V1';
  final int version;
  final bool finished;
  final List<String> playerIds;
  final int targetScore;
  final Map<String, int> scores;
  final int round;

  /// Deals every card this round (the previous round's winner).
  final String starterId;

  /// Names the rank this round (the other player).
  final String callerId;

  /// True while the caller picks a rank; false while cards are turned.
  final bool calling;
  final String? calledRank;
  /// Who must act: the chooser while calling, the starter while dealing.
  final String? currentPlayerId;

  /// Who gets the next card the starter turns.
  final String? receiverId;
  final List<KartaDealt> dealt;
  final String deckCommitment;
  final KartaRoundResult? lastRound;
  final List<String> winnerOrder;

  /// SCORE | RESIGN once finished.
  final String? finishReason;

  String? get winnerId => winnerOrder.isEmpty ? null : winnerOrder.first;
  String? otherThan(String? userId) => playerIds.where((id) => id != userId).firstOrNull;
  int scoreOf(String? userId) => scores[userId] ?? 0;

  /// Cards of the called rank still in the deck (4 at the start of a round).
  int get calledLeft => 4 - dealt.where((d) => d.card.rank == calledRank).length;
  int get cardsLeft => 52 - dealt.length;

  factory KartaGame.fromJson(Map<String, dynamic> json) => KartaGame(
        matchId: json['matchId']?.toString() ?? '',
        version: _int(json['version']),
        finished: json['phase']?.toString() == 'FINISHED',
        playerIds: (json['players'] as List? ?? const []).whereType<Map>().map((p) => p['userId']?.toString() ?? '').toList(),
        targetScore: json['targetScore'] == null ? 3 : _int(json['targetScore']),
        scores: (json['scores'] is Map ? Map<String, dynamic>.from(json['scores'] as Map) : const <String, dynamic>{})
            .map((key, value) => MapEntry(key, _int(value))),
        round: _int(json['round']),
        starterId: json['starterId']?.toString() ?? '',
        callerId: json['callerId']?.toString() ?? '',
        calling: json['roundPhase']?.toString() != 'FLIPPING',
        calledRank: json['calledRank']?.toString(),
        currentPlayerId: json['currentPlayerId']?.toString(),
        receiverId: json['receiverId']?.toString(),
        dealt: KartaDealt.listFrom(json['dealt']),
        deckCommitment: json['deckCommitment']?.toString() ?? '',
        lastRound: KartaRoundResult.fromJson(json['lastRound']),
        winnerOrder: (json['winnerOrder'] as List? ?? const []).map((e) => e.toString()).toList(),
        finishReason: json['finishReason']?.toString(),
        rulesVersion: json['rulesVersion']?.toString() ?? 'KARTA_LATLAT_V1',
      );

  KartaGame copyWith({
    int? version,
    bool? finished,
    Map<String, int>? scores,
    int? round,
    String? starterId,
    String? callerId,
    bool? calling,
    String? calledRank,
    bool clearCalledRank = false,
    String? currentPlayerId,
    bool clearCurrentPlayer = false,
    String? receiverId,
    bool clearReceiver = false,
    List<KartaDealt>? dealt,
    String? deckCommitment,
    KartaRoundResult? lastRound,
    List<String>? winnerOrder,
    String? finishReason,
  }) =>
      KartaGame(
        matchId: matchId,
        version: version ?? this.version,
        finished: finished ?? this.finished,
        playerIds: playerIds,
        targetScore: targetScore,
        scores: scores ?? this.scores,
        round: round ?? this.round,
        starterId: starterId ?? this.starterId,
        callerId: callerId ?? this.callerId,
        calling: calling ?? this.calling,
        calledRank: clearCalledRank ? null : calledRank ?? this.calledRank,
        currentPlayerId: clearCurrentPlayer ? null : currentPlayerId ?? this.currentPlayerId,
        receiverId: clearReceiver ? null : receiverId ?? this.receiverId,
        dealt: dealt ?? this.dealt,
        deckCommitment: deckCommitment ?? this.deckCommitment,
        lastRound: lastRound ?? this.lastRound,
        winnerOrder: winnerOrder ?? this.winnerOrder,
        finishReason: finishReason ?? this.finishReason,
        rulesVersion: rulesVersion,
      );
}

int _int(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
