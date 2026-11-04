/// A pending or resolved challenge as sent by the server.
///
/// `kind` is LOBBY (both players in the lobby), REMATCH (the two players of a
/// finished match) or INVITE (opponent unknown until someone joins the code).
class LobbyChallenge {
  const LobbyChallenge({
    required this.id,
    required this.gameModeId,
    required this.challengerId,
    required this.opponentId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.kind = 'LOBBY',
    this.sourceMatchId,
    this.inviteCode,
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
  final String kind;
  final String? sourceMatchId;
  final String? inviteCode;
  final String? challengerName;
  final String? opponentName;

  /// Set once accepted: the durable match both players enter.
  final String? matchId;

  bool get isRematch => kind == 'REMATCH';
  bool get isInvite => kind == 'INVITE';

  /// Invite code formatted for reading aloud / typing: `ABCDE-FGHJK`.
  String? get displayInviteCode {
    final code = inviteCode;
    if (code == null || code.length < 6) return code;
    final half = code.length ~/ 2;
    return '${code.substring(0, half)}-${code.substring(half)}';
  }

  factory LobbyChallenge.fromJson(Map<String, dynamic> json) {
    String? optional(String key) {
      final value = json[key]?.toString();
      return value == null || value.isEmpty ? null : value;
    }

    return LobbyChallenge(
      id: json['id']?.toString() ?? '',
      gameModeId: json['gameModeId']?.toString() ?? '',
      challengerId: json['challengerId']?.toString() ?? '',
      opponentId: json['opponentId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ?? DateTime.now().toUtc(),
      kind: optional('kind') ?? 'LOBBY',
      sourceMatchId: optional('sourceMatchId'),
      inviteCode: optional('inviteCode'),
      challengerName: optional('challengerName'),
      opponentName: optional('opponentName'),
      matchId: _matchId(json),
    );
  }

  static String? _matchId(Map<String, dynamic> json) {
    final match = json['match'];
    final id = match is Map ? match['id']?.toString() : json['matchId']?.toString();
    return id == null || id.isEmpty ? null : id;
  }
}
