class MatchParticipantSummary {
  const MatchParticipantSummary({
    required this.userId,
    required this.displayName,
    required this.seat,
  });

  final String userId;
  final String displayName;
  final int seat;

  factory MatchParticipantSummary.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final name = user is Map ? user['fullName']?.toString() : null;
    return MatchParticipantSummary(
      userId: json['userId']?.toString() ?? '',
      displayName: name ?? 'Player',
      seat: json['seat'] is int ? json['seat'] as int : int.tryParse(json['seat']?.toString() ?? '') ?? 0,
    );
  }
}
