import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';

/// Karta queue table: the winner keeps dealing, every round pays at once.
const kartaTableRules = 'KARTA_TABLE_V1';

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
    this.gameCode = 'LUDO',
    this.custom = false,
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

  /// Backend game code (LUDO, DAMA). Set by the repository from the request.
  final String gameCode;

  /// An amount a player chose in the lobby (not a catalog stake).
  final bool custom;

  GameMode withGameCode(String code) => GameMode(
        id: id,
        gameId: gameId,
        code: this.code,
        name: name,
        playerCount: playerCount,
        stakeAmountMinor: stakeAmountMinor,
        platformFeeBps: platformFeeBps,
        turnDurationSeconds: turnDurationSeconds,
        rulesVersion: rulesVersion,
        enabled: enabled,
        gameCode: code,
        custom: custom,
      );

  /// A Karta queue table: [playerCount] is its seats; every round is 1v1.
  bool get isKartaTable => rulesVersion == kartaTableRules;

  /// Players in one match (a Karta table round is always two).
  int get matchPlayers => isKartaTable ? 2 : playerCount;

  /// A 3–4 player match that fills by itself from ready players (Ludo).
  bool get isAutoTable => matchPlayers > 2;

  /// Where several play (a 3–4 player match, or a Karta table): no 1v1 requests.
  bool get isMultiplayer => isAutoTable || isKartaTable;

  int get totalPotMinor => stakeAmountMinor * matchPlayers;

  int get estimatedFeeMinor => (totalPotMinor * platformFeeBps) ~/ 10000;

  int get estimatedWinnerPayoutMinor => totalPotMinor - estimatedFeeMinor;

  Map<String, dynamic> toJson() => {
        'id': id,
        'gameId': gameId,
        'code': code,
        'name': name,
        'playerCount': playerCount,
        'stakeAmountMinor': stakeAmountMinor,
        'platformFeeBps': platformFeeBps,
        'turnDurationSeconds': turnDurationSeconds,
        'rulesVersion': rulesVersion,
        'enabled': enabled,
        'gameCode': gameCode,
        'custom': custom,
      };

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
      enabled: json['enabled'] != false,
      gameCode: gameCodeOfMatch(json) ?? json['gameCode']?.toString() ?? 'LUDO',
      custom: json['custom'] == true,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
