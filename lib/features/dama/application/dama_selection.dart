import 'package:friends_game_app/features/dama/domain/dama_models.dart';

/// What the player has picked so far: a piece, then (for an ambiguous
/// multi-capture) the landing squares chosen one by one.
class DamaSelection {
  const DamaSelection({this.from, this.steps = const []});
  final int? from;
  final List<int> steps;

  static const none = DamaSelection();
  bool get isEmpty => from == null;
}

/// Result of a tap: the new selection, and a complete move to send (if any).
typedef DamaTapResult = ({DamaSelection selection, DamaMove? send});

/// Pure tap logic over the server's legal moves. Taps never decide rules;
/// they only pick one of [legal].
abstract final class DamaPicker {
  /// Pieces that may move now (all of them must capture when a capture exists).
  static Set<int> movable(List<DamaMove> legal) => {for (final move in legal) move.from};

  /// Legal moves that still fit the selection.
  static List<DamaMove> candidates(List<DamaMove> legal, DamaSelection selection) {
    if (selection.from == null) return const [];
    return legal.where((move) {
      if (move.from != selection.from || move.path.length <= selection.steps.length) return false;
      for (var i = 0; i < selection.steps.length; i++) {
        if (move.path[i + 1] != selection.steps[i]) return false;
      }
      return true;
    }).toList();
  }

  /// Squares worth tapping: every destination, plus the next landing square
  /// when routes split (so a multi-capture route can be chosen step by step).
  static Set<int> targets(List<DamaMove> legal, DamaSelection selection) {
    final fits = candidates(legal, selection);
    return {
      for (final move in fits) move.to,
      for (final move in fits)
        if (move.path.length > selection.steps.length + 1) move.path[selection.steps.length + 1],
    }..remove(selection.from);
  }

  /// With one movable piece (e.g. a forced capture) it is picked for you.
  static DamaSelection initial(List<DamaMove> legal) {
    final pieces = movable(legal);
    return pieces.length == 1 ? DamaSelection(from: pieces.first) : DamaSelection.none;
  }

  static DamaTapResult tap(List<DamaMove> legal, DamaSelection selection, int square) {
    final fits = candidates(legal, selection);
    if (selection.from != null && square != selection.from) {
      // A destination that only one route reaches: play it.
      final ending = fits.where((move) => move.to == square).toList();
      if (ending.length == 1) return (selection: DamaSelection.none, send: ending.first);
      // Several routes end here: keep the piece; the player picks the route's next landing square.
      if (ending.length > 1 && fits.any((move) => move.path.length > selection.steps.length + 2)) {
        return (selection: selection, send: null);
      }
      // The next landing square of a split route: narrow down.
      final nextIndex = selection.steps.length + 1;
      final narrowed = fits.where((move) => move.path.length > nextIndex && move.path[nextIndex] == square).toList();
      if (narrowed.isNotEmpty) {
        final next = DamaSelection(from: selection.from, steps: [...selection.steps, square]);
        final remaining = candidates(legal, next);
        if (remaining.length == 1) return (selection: DamaSelection.none, send: remaining.first);
        return (selection: next, send: null);
      }
    }
    if (movable(legal).contains(square)) {
      // Tapping the selected piece again deselects it.
      if (selection.from == square && selection.steps.isEmpty) return (selection: DamaSelection.none, send: null);
      return (selection: DamaSelection(from: square), send: null);
    }
    return (selection: DamaSelection.none, send: null);
  }
}
