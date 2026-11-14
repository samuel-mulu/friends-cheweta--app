import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/features/ludo/application/ludo_scene.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_board_spec.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';

enum LudoHaptic { light, medium, heavy }

/// What the player should hear/feel at one moment of the presentation.
class LudoFeedback {
  const LudoFeedback({this.sound, this.volume = 1.0, this.haptic});
  final GameSound? sound;
  final double volume;
  final LudoHaptic? haptic;

  static const none = LudoFeedback();
}

/// Feedback when a scene starts. Landing sounds (safe / capture / home) are
/// not here: they play on the walker's final hop, see [landingFeedback].
LudoFeedback sceneStartFeedback(
  LudoScene scene, {
  required String? me,
  bool fromOptimisticTap = false,
}) {
  final mine = me != null && scene.playerId == me;
  switch (scene) {
    case LudoMatchStartedScene():
      return const LudoFeedback(sound: GameSound.matchStart);
    case LudoDiceScene():
      // The owner's die already clicked when they tapped it.
      if (mine && fromOptimisticTap) return LudoFeedback.none;
      return LudoFeedback(sound: GameSound.diceRoll, volume: mine ? 1.0 : 0.55);
    case LudoExtraRollScene():
      return LudoFeedback(sound: GameSound.extraRoll, volume: mine ? 1.0 : 0.5);
    case LudoNoticeScene():
      return mine ? const LudoFeedback(haptic: LudoHaptic.medium) : LudoFeedback.none;
    case LudoMatchEndScene(:final winnerOrder):
      final won = me != null && winnerOrder.isNotEmpty && winnerOrder.first == me;
      return LudoFeedback(sound: won ? GameSound.win : GameSound.lose, haptic: won ? LudoHaptic.heavy : null);
    case LudoMoveScene():
    case LudoCaptureScene():
    case LudoFinishScene():
    case LudoTurnScene():
    case LudoApplyScene():
      return LudoFeedback.none;
  }
}

/// Feedback for the walker's final hop: exactly one of home, capture, safe or nothing.
LudoFeedback landingFeedback(
  LudoMoveScene scene, {
  required String? me,
  required LudoBoardSpec board,
  required Map<String, String> tokenOwners,
}) {
  final move = scene.move;
  final mine = me != null && move.playerId == me;
  if (move.finishes) {
    return LudoFeedback(sound: GameSound.home, haptic: mine ? LudoHaptic.light : null);
  }
  if (move.captures) {
    final victimIsMe = me != null && move.capturedTokenIds.any((id) => tokenOwners[id] == me);
    return LudoFeedback(
      sound: GameSound.capture,
      haptic: victimIsMe ? LudoHaptic.heavy : (mine ? LudoHaptic.medium : null),
    );
  }
  final after = move.tokenAfter;
  if (board.isSafe(after.color, after.progress)) return const LudoFeedback(sound: GameSound.safe, volume: 0.8);
  return LudoFeedback.none;
}

/// One click per square; the owner's token is a little louder.
LudoFeedback stepFeedback(LudoMoveScene scene, {required String? me}) =>
    LudoFeedback(sound: GameSound.step, volume: me != null && scene.move.playerId == me ? 0.5 : 0.35);

/// "Your turn" plays once the board is quiet and it really is my roll.
bool shouldPingMyTurn({
  required LudoGameState authoritative,
  required bool timelineIdle,
  required String? me,
}) =>
    timelineIdle &&
    me != null &&
    authoritative.phase == LudoMatchPhase.playing &&
    authoritative.currentPlayerId == me &&
    authoritative.turnPhase == LudoTurnPhase.waitingForRoll;
