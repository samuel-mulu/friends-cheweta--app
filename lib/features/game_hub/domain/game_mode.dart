class GameMode {
  const GameMode({
    required this.id,
    required this.gameId,
    required this.code,
    required this.name,
    required this.playerCount,
    required this.stakeAmountMinor,
    required this.platformFeeBps,
    required this.turnDurationSeconds,
    required this.rulesVersion,
    required this.enabled,
  });

  final String id;
  final String gameId;
  final String code;
  final String name;
  final int playerCount;
  final int stakeAmountMinor;
  final int platformFeeBps;
  final int turnDurationSeconds;
  final String rulesVersion;
  final bool enabled;

  int get totalPotMinor => stakeAmountMinor * playerCount;

  int get estimatedFeeMinor => (totalPotMinor * platformFeeBps) ~/ 10000;

  int get estimatedWinnerPayoutMinor => totalPotMinor - estimatedFeeMinor;

  factory GameMode.fromJson(Map<String, dynamic> json) {
    return GameMode(
      id: json['id']?.toString() ?? '',
      gameId: json['gameId']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      playerCount: _asInt(json['playerCount']),
      stakeAmountMinor: _asInt(json['stakeAmountMinor']),
      platformFeeBps: _asInt(json['platformFeeBps']),
      turnDurationSeconds: _asInt(json['turnDurationSeconds']),
      rulesVersion: json['rulesVersion']?.toString() ?? '',
      enabled: json['enabled'] == true,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
