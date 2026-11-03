import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/matchmaking/domain/match_participant_summary.dart';

class MatchSummary {
  const MatchSummary({
    required this.id,
    required this.status,
    required this.stakeAmountMinor,
    required this.rulesVersion,
    required this.gameMode,
    this.participants = const [],
    this.sessionCode,
  });

  final String id;
  final String status;
  final int stakeAmountMinor;
  final String rulesVersion;
  final GameMode gameMode;
  final List<MatchParticipantSummary> participants;
  final String? sessionCode;

  String? opponentName(String selfUserId) {
    for (final participant in participants) {
      if (participant.userId != selfUserId) return participant.displayName;
    }
    return null;
  }

  factory MatchSummary.fromJson(Map<String, dynamic> json) {
    final rawMode = json['gameMode'];
    final rawParticipants = json['participants'];
    return MatchSummary(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      stakeAmountMinor: int.tryParse(json['stakeAmountMinor']?.toString() ?? '') ?? 0,
      rulesVersion: json['rulesVersion']?.toString() ?? '',
      sessionCode: json['sessionCode']?.toString(),
      gameMode: rawMode is Map
          ? GameMode.fromJson(Map<String, dynamic>.from(rawMode))
          : const GameMode(
              id: '',
              gameId: '',
              code: '',
              name: 'Ludo',
              playerCount: 2,
              stakeAmountMinor: 0,
              platformFeeBps: 0,
              turnDurationSeconds: 30,
              rulesVersion: 'LUDO_CLASSIC_V1',
              enabled: true,
            ),
      participants: rawParticipants is List
          ? rawParticipants
              .whereType<Map>()
              .map((item) => MatchParticipantSummary.fromJson(Map<String, dynamic>.from(item)))
              .toList(growable: false)
          : const [],
    );
  }
}
