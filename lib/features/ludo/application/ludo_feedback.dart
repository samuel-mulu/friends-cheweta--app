import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';

enum LudoHaptic { light, medium, heavy }

/// What the player should hear/feel when a presentation event is shown.
class LudoFeedback {
  const LudoFeedback({this.sound, this.volume = 1.0, this.haptic});
  final GameSound? sound;
  final double volume;
  final LudoHaptic? haptic;

  static const none = LudoFeedback();
}

/// Pure mapping, driven by the same presentation queue as the animations so
/// sound and motion stay in sync. Step sounds come from the walking token.
LudoFeedback feedbackFor(
  LudoPresentationEvent event, {
  required String? me,
  required List<String> winnerOrder,
  required Map<String, String> tokenOwners,
}) {
  final mine = me != null && event.playerId == me;
  switch (event.kind) {
    case LudoPresentationKind.matchStarted:
      return const LudoFeedback(sound: GameSound.matchStart);
    case LudoPresentationKind.dice:
      return LudoFeedback(sound: GameSound.diceRoll, volume: mine ? 1.0 : 0.55);
    case LudoPresentationKind.move:
      final after = event.move?.tokenAfter;
      if (after == null || (event.move?.capturedTokenIds.isNotEmpty ?? false)) return LudoFeedback.none;
      final onSafe = after.progress >= 0 &&
          after.progress <= 51 &&
          LudoBoardGeometry.safeGlobalSquares.contains((after.color.startIndex + after.progress) % 52);
      return onSafe ? const LudoFeedback(sound: GameSound.safe, volume: 0.8) : LudoFeedback.none;
    case LudoPresentationKind.capture:
      final victimIsMe = me != null && event.tokenIds.any((id) => tokenOwners[id] == me);
      return LudoFeedback(
        sound: GameSound.capture,
        haptic: mine || victimIsMe ? (victimIsMe ? LudoHaptic.heavy : LudoHaptic.medium) : null,
      );
    case LudoPresentationKind.finish:
      return LudoFeedback(sound: GameSound.home, haptic: mine ? LudoHaptic.medium : null);
    case LudoPresentationKind.extraRoll:
      return LudoFeedback(sound: GameSound.extraRoll, volume: mine ? 1.0 : 0.5);
    case LudoPresentationKind.turn:
      return mine ? const LudoFeedback(sound: GameSound.yourTurn, haptic: LudoHaptic.light) : LudoFeedback.none;
    case LudoPresentationKind.matchFinished:
      final won = me != null && winnerOrder.isNotEmpty && winnerOrder.first == me;
      return LudoFeedback(sound: won ? GameSound.win : GameSound.lose, haptic: won ? LudoHaptic.heavy : null);
  }
}
