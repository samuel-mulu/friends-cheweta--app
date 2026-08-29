import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

class LudoGridCell {
  const LudoGridCell(this.row, this.column);
  final int row;
  final int column;
}

abstract final class LudoBoardGeometry {
  static const gridSize = 15;
  static const safeGlobalSquares = <int>{0, 8, 13, 21, 26, 34, 39, 47};

  static const track = <LudoGridCell>[
    LudoGridCell(6, 1), LudoGridCell(6, 2), LudoGridCell(6, 3), LudoGridCell(6, 4), LudoGridCell(6, 5),
    LudoGridCell(5, 6), LudoGridCell(4, 6), LudoGridCell(3, 6), LudoGridCell(2, 6), LudoGridCell(1, 6),
    LudoGridCell(0, 6), LudoGridCell(0, 7), LudoGridCell(0, 8),
    LudoGridCell(1, 8), LudoGridCell(2, 8), LudoGridCell(3, 8), LudoGridCell(4, 8), LudoGridCell(5, 8),
    LudoGridCell(6, 9), LudoGridCell(6, 10), LudoGridCell(6, 11), LudoGridCell(6, 12), LudoGridCell(6, 13),
    LudoGridCell(6, 14), LudoGridCell(7, 14), LudoGridCell(8, 14),
    LudoGridCell(8, 13), LudoGridCell(8, 12), LudoGridCell(8, 11), LudoGridCell(8, 10), LudoGridCell(8, 9),
    LudoGridCell(9, 8), LudoGridCell(10, 8), LudoGridCell(11, 8), LudoGridCell(12, 8), LudoGridCell(13, 8),
    LudoGridCell(14, 8), LudoGridCell(14, 7), LudoGridCell(14, 6),
    LudoGridCell(13, 6), LudoGridCell(12, 6), LudoGridCell(11, 6), LudoGridCell(10, 6), LudoGridCell(9, 6),
    LudoGridCell(8, 5), LudoGridCell(8, 4), LudoGridCell(8, 3), LudoGridCell(8, 2), LudoGridCell(8, 1),
    LudoGridCell(8, 0), LudoGridCell(7, 0), LudoGridCell(6, 0),
  ];

  static const homePaths = <LudoColor, List<LudoGridCell>>{
    LudoColor.red: [
      LudoGridCell(7, 1), LudoGridCell(7, 2), LudoGridCell(7, 3), LudoGridCell(7, 4), LudoGridCell(7, 5),
    ],
    LudoColor.green: [
      LudoGridCell(1, 7), LudoGridCell(2, 7), LudoGridCell(3, 7), LudoGridCell(4, 7), LudoGridCell(5, 7),
    ],
    LudoColor.yellow: [
      LudoGridCell(7, 13), LudoGridCell(7, 12), LudoGridCell(7, 11), LudoGridCell(7, 10), LudoGridCell(7, 9),
    ],
    LudoColor.blue: [
      LudoGridCell(13, 7), LudoGridCell(12, 7), LudoGridCell(11, 7), LudoGridCell(10, 7), LudoGridCell(9, 7),
    ],
  };

  static Offset tokenCenter({
    required LudoColor color,
    required int progress,
    required int baseIndex,
    required double boardSize,
    int stackIndex = 0,
  }) {
    final cell = boardSize / gridSize;
    Offset center;

    if (progress < 0) {
      center = _baseCenter(color, baseIndex, cell);
    } else if (progress <= 51) {
      final global = (color.startIndex + progress) % 52;
      final grid = track[global];
      center = Offset((grid.column + .5) * cell, (grid.row + .5) * cell);
    } else if (progress <= 56) {
      final path = homePaths[color]!;
      final index = (progress - 52).clamp(0, path.length - 1).toInt();
      final grid = path[index];
      center = Offset((grid.column + .5) * cell, (grid.row + .5) * cell);
    } else {
      center = _finishCenter(color, cell);
    }

    if (stackIndex <= 0) return center;
    final direction = switch (stackIndex % 4) {
      0 => const Offset(-1, -1),
      1 => const Offset(1, -1),
      2 => const Offset(-1, 1),
      _ => const Offset(1, 1),
    };
    return center + direction * (cell * .13);
  }

  static Offset _baseCenter(LudoColor color, int index, double cell) {
    const positions = <Offset>[
      Offset(1.8, 1.8),
      Offset(4.2, 1.8),
      Offset(1.8, 4.2),
      Offset(4.2, 4.2),
    ];
    final local = positions[index.clamp(0, 3).toInt()];
    final origin = switch (color) {
      LudoColor.red => Offset.zero,
      LudoColor.green => const Offset(9, 0),
      LudoColor.yellow => const Offset(9, 9),
      LudoColor.blue => const Offset(0, 9),
    };
    return Offset((origin.dx + local.dx) * cell, (origin.dy + local.dy) * cell);
  }

  static Offset _finishCenter(LudoColor color, double cell) {
    final local = switch (color) {
      LudoColor.red => const Offset(6.8, 7.5),
      LudoColor.green => const Offset(7.5, 6.8),
      LudoColor.yellow => const Offset(8.2, 7.5),
      LudoColor.blue => const Offset(7.5, 8.2),
    };
    return Offset(local.dx * cell, local.dy * cell);
  }
}
