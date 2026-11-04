import 'dart:ui';

import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

/// Screen corners, clockwise from top-left.
enum LudoCorner { topLeft, topRight, bottomRight, bottomLeft }

/// How the board is presented to one viewer.
///
/// The painted board has fixed corners (red TL, green TR, yellow BR, blue BL).
/// Like classic Ludo apps we rotate it so the viewer's own color always sits
/// bottom-left, which keeps "my dice" in the same place for 2, 3 or 4 players.
/// Pure presentation: game state and server coordinates never rotate.
class LudoBoardOrientation {
  const LudoBoardOrientation._(this.quarterTurns);

  /// Clockwise quarter turns applied to the painted board.
  final int quarterTurns;

  static const identity = LudoBoardOrientation._(0);

  factory LudoBoardOrientation.forViewer(LudoColor? myColor) {
    if (myColor == null) return identity; // spectators / unknown: unrotated
    final turns = (LudoCorner.bottomLeft.index - _paintedCorner(myColor).index) % 4;
    return LudoBoardOrientation._(turns);
  }

  /// Where [color]'s yard appears on screen after rotation.
  LudoCorner cornerOf(LudoColor color) => LudoCorner.values[(_paintedCorner(color).index + quarterTurns) % 4];

  /// Rotate a point on a square board of [size] clockwise by [quarterTurns].
  Offset rotate(Offset point, double size) {
    var p = point;
    for (var i = 0; i < quarterTurns; i++) {
      p = Offset(size - p.dy, p.dx);
    }
    return p;
  }

  static LudoCorner _paintedCorner(LudoColor color) => switch (color) {
        LudoColor.red => LudoCorner.topLeft,
        LudoColor.green => LudoCorner.topRight,
        LudoColor.yellow => LudoCorner.bottomRight,
        LudoColor.blue => LudoCorner.bottomLeft,
      };
}
