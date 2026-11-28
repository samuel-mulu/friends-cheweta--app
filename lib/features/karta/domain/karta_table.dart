/// A Karta queue table (rules KARTA_TABLE_V1), as the server sends it.
///
/// Up to [maxSeats] players: the starter deals, the receiver calls the rank,
/// the rest wait in [queue] (next receiver first). Each round is a 1v1 match
/// that pays at once; the winner keeps dealing and the loser waits last.
class KartaTable {
  const KartaTable({
    required this.id,
    required this.gameModeId,
    required this.stakeMinor,
    required this.maxSeats,
    required this.freeSeats,
    required this.status,
    required this.starterId,
    required this.receiverId,
    required this.queue,
    required this.round,
    required this.matchId,
    required this.players,
    this.raise,
    this.last,
  });

  final String id;
  final String gameModeId;
  final int stakeMinor;
  final int maxSeats;
  final int freeSeats;

  /// PLAYING (a round in play), BETWEEN (the pause after a round) or CLOSED.
  final String status;
  final String starterId;
  final String? receiverId;
  final List<String> queue;
  final int round;
  final String? matchId;

  /// Everyone seated, in turn order (starter, receiver, queue).
  final List<KartaTablePlayer> players;
  final KartaTableRaise? raise;
  final KartaTableRound? last;

  bool get isPlaying => status == 'PLAYING';
  bool get isClosed => status == 'CLOSED';
  int get seated => players.length;

  /// What [userId] does at this table right now.
  KartaSeatRole roleOf(String? userId) {
    if (userId == null) return KartaSeatRole.none;
    if (userId == starterId) return KartaSeatRole.starter;
    if (userId == receiverId) return KartaSeatRole.receiver;
    return queue.contains(userId) ? KartaSeatRole.waiting : KartaSeatRole.none;
  }

  /// 1 for the next to play, 2 after them… (0 when not waiting).
  int queuePlace(String? userId) => userId == null ? 0 : queue.indexOf(userId) + 1;

  /// One of the two players of the round in play.
  bool inRound(String? userId) => isPlaying && (userId == starterId || userId == receiverId);

  String nameOf(String userId) {
    for (final player in players) {
      if (player.userId == userId) return player.fullName;
    }
    return 'Player';
  }

  factory KartaTable.fromJson(Map<String, dynamic> json) {
    final raise = json['raise'];
    final last = json['last'];
    return KartaTable(
      id: json['id']?.toString() ?? '',
      gameModeId: json['gameModeId']?.toString() ?? '',
      stakeMinor: _int(json['stakeMinor']),
      maxSeats: _int(json['maxSeats'], 4),
      freeSeats: _int(json['freeSeats']),
      status: json['status']?.toString() ?? 'PLAYING',
      starterId: json['starterId']?.toString() ?? '',
      receiverId: json['receiverId']?.toString(),
      queue: [for (final id in json['queue'] as List? ?? const []) id.toString()],
      round: _int(json['round'], 1),
      matchId: json['matchId']?.toString(),
      players: [
        for (final item in (json['players'] as List? ?? const []).whereType<Map>())
          KartaTablePlayer(userId: item['userId']?.toString() ?? '', fullName: item['fullName']?.toString() ?? 'Player'),
      ],
      raise: raise is Map ? KartaTableRaise(amountMinor: _int(raise['amountMinor']), byUserId: raise['byUserId']?.toString() ?? '') : null,
      last: last is Map
          ? KartaTableRound(
              round: _int(last['round']),
              winnerId: last['winnerId']?.toString() ?? '',
              loserId: last['loserId']?.toString() ?? '',
              payoutMinor: _int(last['payoutMinor']),
            )
          : null,
    );
  }

  static int _int(Object? value, [int fallback = 0]) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? fallback;
}

enum KartaSeatRole { starter, receiver, waiting, none }

class KartaTablePlayer {
  const KartaTablePlayer({required this.userId, required this.fullName});
  final String userId;
  final String fullName;
}

/// A raise one current player asked for; the other answers.
class KartaTableRaise {
  const KartaTableRaise({required this.amountMinor, required this.byUserId});
  final int amountMinor;
  final String byUserId;
}

/// The last round: who won it and what they were paid.
class KartaTableRound {
  const KartaTableRound({required this.round, required this.winnerId, required this.loserId, required this.payoutMinor});
  final int round;
  final String winnerId;
  final String loserId;
  final int payoutMinor;
}
