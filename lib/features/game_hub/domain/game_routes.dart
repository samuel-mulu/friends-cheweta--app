/// Live games, identified by their backend code. Each game owns the routes
/// `/<code>`, `/<code>/matchmaking`, `/<code>/match/:id`, `/<code>/result/:id`.
abstract final class GameCodes {
  static const ludo = 'LUDO';
  static const dama = 'DAMA';
}

abstract final class GameRoutes {
  static String lobby(String gameCode) => '/${gameCode.toLowerCase()}';
  static String matchmaking(String gameCode) => '${lobby(gameCode)}/matchmaking';
  static String match(String gameCode, String matchId) => '${lobby(gameCode)}/match/$matchId';
  static String result(String gameCode, String matchId) => '${lobby(gameCode)}/result/$matchId';

  static String displayName(String gameCode) => switch (gameCode) {
        GameCodes.dama => 'Dama',
        _ => 'Ludo',
      };
}

/// `match.game.code` (or `gameCode`) from a server match payload, if present.
String? gameCodeOfMatch(Object? match) {
  if (match is! Map) return null;
  final game = match['game'];
  final code = game is Map ? game['code'] : match['gameCode'];
  final text = code?.toString();
  return text == null || text.isEmpty ? null : text;
}
