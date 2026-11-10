import 'package:friends_game_app/features/dama/application/dama_match_controller.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';

/// Pure view model for the Dama screen: who moves, what can be tapped, and
/// the words on the banner. No widgets, so it is unit tested directly.
class DamaPresenter {
  DamaPresenter({required this.match, required this.me, this.connected = true});
  final DamaMatchViewState match;
  final String? me;
  final bool connected;

  DamaGame get game => match.game!;
  DamaColor get myColor => game.colorOf(me) ?? DamaColor.light;

  /// Dark sees the board turned so their own pieces are at the bottom.
  bool get flipped => myColor == DamaColor.dark;

  String? get opponentId => game.playerOf(myColor.opponent);
  String opponentName() => match.participant(opponentId)?.shortName ?? 'Opponent';

  bool get isMyTurn => !game.finished && game.currentPlayerId == me;

  /// Tappable only when it is my move, connected and nothing is in flight.
  bool get canAct => isMyTurn && connected && match.pendingCommandId == null && !match.recovering;

  List<DamaMove> get legal => canAct ? match.legalMoves : const [];
  bool get mustCapture => isMyTurn && match.legalMoves.any((move) => move.isCapture);

  /// Most pieces the compulsory capture takes (shown as "Capture 2!").
  int get captureCount => match.legalMoves.fold(0, (most, move) => move.captured.length > most ? move.captured.length : most);

  bool get iWon => game.finished && game.winnerId == me;

  String get banner {
    if (game.finished) {
      if (game.isDraw) return 'DRAW';
      return iWon ? 'YOU WON!' : '${opponentName().toUpperCase()} WON';
    }
    if (isMyTurn) return mustCapture ? (captureCount > 1 ? 'CAPTURE $captureCount!' : 'CAPTURE!') : 'YOUR MOVE';
    return "${opponentName().toUpperCase()}'S MOVE";
  }

  String get hint {
    if (game.finished) {
      return switch (game.finishReason) {
        'NO_PIECES' => iWon ? 'You took every piece.' : 'All your pieces were taken.',
        'NO_MOVES' => iWon ? '${opponentName()} has no move left.' : 'You have no move left.',
        'RESIGN' => iWon ? '${opponentName()} resigned.' : 'You resigned.',
        'DRAW_RULE' => 'Draw: 20 moves each without a capture. Stakes are returned.',
        _ => 'Match finished.',
      };
    }
    if (!connected) return 'Reconnecting…';
    if (match.recovering) return 'Syncing the board…';
    if (!isMyTurn) return 'Waiting for ${opponentName()}…';
    if (match.pendingCommandId != null) return 'Sending your move…';
    if (mustCapture) {
      return captureCount > 1 ? 'Capture is compulsory: take the most pieces.' : 'Capture is compulsory.';
    }
    return 'Tap a piece, then a highlighted square.';
  }

  /// Why a tap did nothing (never fail silently).
  String? get tapExplanation {
    if (game.finished) return null;
    if (!connected) return 'Reconnecting… try again in a moment.';
    if (!isMyTurn) return 'Wait for your turn.';
    if (mustCapture) return 'You must capture with a glowing piece.';
    return 'Pick one of your highlighted pieces.';
  }

  /// Draw-rule progress: plies left without a capture or man move (shown late).
  int get pliesBeforeDraw => 40 - game.pliesSinceProgress;
}
