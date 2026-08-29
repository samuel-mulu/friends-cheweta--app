class ReadyPlayer {
  const ReadyPlayer({
    required this.ticketId,
    required this.userId,
    required this.displayName,
    required this.readyAtMs,
    required this.stakeAmountMinor,
    this.isSelf = false,
  });

  final String ticketId;
  final String userId;
  final String displayName;
  final int readyAtMs;
  final int stakeAmountMinor;
  final bool isSelf;

  factory ReadyPlayer.fromJson(Map<String, dynamic> json) {
    return ReadyPlayer(
      ticketId: json['ticketId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Player',
      readyAtMs: int.tryParse(json['readyAtMs']?.toString() ?? '') ?? 0,
      stakeAmountMinor: int.tryParse(json['stakeAmountMinor']?.toString() ?? '') ?? 0,
      isSelf: json['isSelf'] == true,
    );
  }
}
