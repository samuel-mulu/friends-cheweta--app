import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';

/// The board after a move the server already accepted: the piece leaves its
/// square, captured pieces are removed, and it is crowned if [promoted].
/// (Presentation only: legality is never decided here.)
String applyDamaMove(String board, DamaMove move, {required bool promoted}) {
  final cells = board.split('');
  final piece = DamaPiece.fromCell(cells[move.from]);
  if (piece == null) return board;
  cells[move.from] = '.';
  for (final square in move.captured) {
    cells[square] = '.';
  }
  cells[move.to] = (promoted ? DamaPiece(piece.color, king: true) : piece).cell;
  return cells.join();
}

/// Pure: the game after one server event at [version].
DamaGame reduceDamaEvent(DamaGame game, RealtimeEvent event, int version) {
  final data = event.data;
  switch (event.name) {
    case 'dama:piece_moved':
      final raw = data['move'];
      if (raw is! Map) return game.copyWith(version: version);
      final move = DamaMove.fromJson(Map<String, dynamic>.from(raw));
      final movedMan = game.pieceAt(move.from)?.king == false;
      final mover = game.colorOf(data['playerId']?.toString());
      return game.copyWith(
        version: version,
        board: applyDamaMove(game.board, move, promoted: data['promoted'] == true),
        lastMove: move,
        plyCount: game.plyCount + 1,
        pliesSinceProgress: move.isCapture || movedMan ? 0 : game.pliesSinceProgress + 1,
        // The turn passes; TURN_STARTED or MATCH_FINISHED (same version) follows.
        currentPlayerId: mover == null ? game.currentPlayerId : game.playerOf(mover.opponent),
      );
    case 'dama:turn_started':
      return game.copyWith(version: version, currentPlayerId: data['playerId']?.toString());
    case 'match:finished':
      return game.copyWith(
        version: version,
        finished: true,
        clearCurrentPlayer: true,
        winnerOrder: (data['winnerOrder'] as List? ?? const []).map((e) => e.toString()).toList(),
        result: data['result']?.toString(),
        finishReason: data['reason']?.toString(),
      );
    default:
      return game.copyWith(version: version);
  }
}
