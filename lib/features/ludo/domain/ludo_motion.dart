import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';

/// Shared timing for board presentation, so the animation queue, the token
/// walker and sounds agree on how long a move takes.
abstract final class LudoMotion {
  /// 1.0 = normal, 0.6 = fast (player preference, see LudoFastAnimations).
  static double speed = 1.0;

  static Duration _scaled(int ms) => Duration(milliseconds: (ms * speed).round());

  static Duration get stepDuration => _scaled(150);
  static Duration get settle => _scaled(120);
  static Duration get diceRoll => _scaled(650);
  static Duration get captureFlight => _scaled(420);

  /// Progress values a token visits, including where it starts.
  /// Leaving the yard (-1) is one hop onto the start square.
  static List<int> path(LudoMoveResolution move) {
    final from = move.tokenBefore.progress;
    final to = move.tokenAfter.progress;
    if (from < 0) return [from, to < 0 ? from : 0];
    if (to <= from) return [from, to];
    return [for (var p = from; p <= to; p++) p];
  }

  static int steps(LudoMoveResolution move) => path(move).length - 1;

  static Duration moveDuration(LudoMoveResolution? move) {
    final count = move == null ? 1 : steps(move).clamp(1, 7);
    return stepDuration * count + settle;
  }
}
