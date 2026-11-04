import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';

/// Shared timing for board presentation, so the animation queue, the token
/// walker and sounds agree on how long a move takes.
abstract final class LudoMotion {
  static const stepDuration = Duration(milliseconds: 150);
  static const settle = Duration(milliseconds: 120);
  static const diceRoll = Duration(milliseconds: 650);
  static const captureFlight = Duration(milliseconds: 420);

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
