import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';

enum LudoNoticeKind { noLegalMove, thirdSix }

/// One thing the board shows, in order. Server events become scenes; the
/// timeline plays them one at a time and advances the *presented* snapshot as
/// each scene starts (or, for moves and captures, when it ends), so nothing on
/// the board ever jumps ahead of what the player is watching.
sealed class LudoScene {
  const LudoScene(this.event);

  final RealtimeEvent event;

  String? get playerId => event.data['playerId']?.toString();

  /// Input waits for blocking scenes (dice, walks, captures, home bursts).
  bool get blocking => false;

  /// The presented snapshot is reduced when this scene *ends* (the token is
  /// still at its old square while it walks).
  bool get appliesAtEnd => false;

  /// A widget reports completion; the timer is only a safety net.
  bool get widgetDriven => false;

  /// Stage time at normal speed (before any catch-up factor).
  Duration get nominal;
}

/// State-only event (legal moves, resignation, tie…): applied in order, no stage time.
final class LudoApplyScene extends LudoScene {
  const LudoApplyScene(super.event);
  @override
  Duration get nominal => Duration.zero;
}

final class LudoMatchStartedScene extends LudoScene {
  const LudoMatchStartedScene(super.event);
  @override
  Duration get nominal => const Duration(milliseconds: 250);
}

final class LudoDiceScene extends LudoScene {
  const LudoDiceScene(super.event, {required this.value, required this.startRoll});
  final int value;
  final bool startRoll;
  @override
  bool get blocking => true;
  @override
  bool get widgetDriven => true;
  @override
  Duration get nominal => LudoMotion.diceRoll;
}

final class LudoMoveScene extends LudoScene {
  const LudoMoveScene(super.event, {required this.move, required this.includeCaptures});
  final LudoMoveResolution move;

  /// False when a [LudoCaptureScene] follows: captured tokens stay on the
  /// square until their own flight home.
  final bool includeCaptures;

  List<int> get path => LudoMotion.path(move);
  @override
  bool get blocking => true;
  @override
  bool get appliesAtEnd => true;
  @override
  bool get widgetDriven => true;
  @override
  Duration get nominal => LudoMotion.moveDuration(move);
}

final class LudoCaptureScene extends LudoScene {
  const LudoCaptureScene(super.event, {required this.attackerTokenId, required this.capturedTokenIds});
  final String attackerTokenId;
  final List<String> capturedTokenIds;
  @override
  bool get blocking => true;
  @override
  bool get appliesAtEnd => true;
  @override
  bool get widgetDriven => true;
  @override
  Duration get nominal => LudoMotion.captureFlight;
}

final class LudoFinishScene extends LudoScene {
  const LudoFinishScene(super.event, {required this.tokenId});
  final String tokenId;
  @override
  bool get blocking => true;
  @override
  Duration get nominal => const Duration(milliseconds: 450);
}

final class LudoExtraRollScene extends LudoScene {
  const LudoExtraRollScene(super.event);
  @override
  Duration get nominal => const Duration(milliseconds: 150);
}

final class LudoTurnScene extends LudoScene {
  const LudoTurnScene(super.event);
  @override
  Duration get nominal => const Duration(milliseconds: 120);
}

final class LudoNoticeScene extends LudoScene {
  const LudoNoticeScene(super.event, {required this.kind});
  final LudoNoticeKind kind;
  @override
  Duration get nominal => const Duration(milliseconds: 700);
}

final class LudoMatchEndScene extends LudoScene {
  const LudoMatchEndScene(super.event, {required this.winnerOrder});
  final List<String> winnerOrder;
  @override
  Duration get nominal => const Duration(milliseconds: 900);
}

/// Server event → scenes. A move carries its capture and home burst as
/// follow-up scenes, so `ludo:token_captured` / `ludo:token_finished` add
/// nothing (they repeat what the move already said).
List<LudoScene> scenesForEvent(RealtimeEvent event) {
  final data = event.data;
  switch (event.name) {
    case 'ludo:starting_roll':
    case 'ludo:dice_rolled':
      final value = int.tryParse(data['diceValue']?.toString() ?? '');
      if (value == null) return [LudoApplyScene(event)];
      return [LudoDiceScene(event, value: value, startRoll: event.name == 'ludo:starting_roll')];
    case 'ludo:token_moved':
      final raw = data['move'];
      if (raw is! Map) return [LudoApplyScene(event)];
      final move = LudoMoveResolution.fromJson(Map<String, dynamic>.from(raw));
      return [
        LudoMoveScene(event, move: move, includeCaptures: !move.captures),
        if (move.captures)
          LudoCaptureScene(event, attackerTokenId: move.tokenId, capturedTokenIds: move.capturedTokenIds),
        if (move.finishes) LudoFinishScene(event, tokenId: move.tokenId),
      ];
    case 'ludo:token_captured':
    case 'ludo:token_finished':
      return const [];
    case 'match:started':
      return [LudoMatchStartedScene(event)];
    case 'ludo:turn_started':
      return [LudoTurnScene(event)];
    case 'ludo:extra_roll_granted':
      return [LudoExtraRollScene(event)];
    case 'ludo:no_legal_move':
      return [LudoNoticeScene(event, kind: LudoNoticeKind.noLegalMove)];
    case 'ludo:third_six_forfeited':
      return [LudoNoticeScene(event, kind: LudoNoticeKind.thirdSix)];
    case 'match:finished':
      return [
        LudoMatchEndScene(
          event,
          winnerOrder: (data['winnerOrder'] as List? ?? const []).map((e) => e.toString()).toList(growable: false),
        ),
      ];
    default:
      return [LudoApplyScene(event)];
  }
}
