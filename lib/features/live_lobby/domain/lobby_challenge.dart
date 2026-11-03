import 'package:friends_game_app/features/matchmaking/domain/match_summary.dart';

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
    this.match,
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
  final MatchSummary? match;

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
      match: json['match'] is Map ? MatchSummary.fromJson(Map<String, dynamic>.from(json['match'] as Map)) : null,
    );
  }
}
