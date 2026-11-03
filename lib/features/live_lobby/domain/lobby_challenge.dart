class LobbyChallenge {
  const LobbyChallenge({
    required this.id,
    required this.gameModeId,
    required this.challengerId,
    required this.opponentId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.challengerName,
    this.opponentName,
    this.matchId,
  });

  final String id;
  final String gameModeId;
  final String challengerId;
  final String opponentId;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? challengerName;
  final String? opponentName;
  /// Set once accepted: the durable match both players enter.
  final String? matchId;

  factory LobbyChallenge.fromJson(Map<String, dynamic> json) {
    return LobbyChallenge(
      id: json['id']?.toString() ?? '',
      gameModeId: json['gameModeId']?.toString() ?? '',
      challengerId: json['challengerId']?.toString() ?? '',
      opponentId: json['opponentId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
      challengerName: json['challengerName']?.toString(),
      opponentName: json['opponentName']?.toString(),
      matchId: _matchId(json),
    );
  }

  static String? _matchId(Map<String, dynamic> json) {
    final match = json['match'];
    final id = match is Map ? match['id']?.toString() : json['matchId']?.toString();
    return id == null || id.isEmpty ? null : id;
  }
}
