import 'package:flutter/material.dart';

enum LudoColor { red, green, yellow, blue }

extension LudoColorX on LudoColor {
  /// Vivid classic Ludo palette: game colors, independent of the app theme.
  Color get color => switch (this) {
        LudoColor.red => const Color(0xFFE53935),
        LudoColor.green => const Color(0xFF1FA35A),
        LudoColor.yellow => const Color(0xFFF5B800),
        LudoColor.blue => const Color(0xFF1E88E5),
      };

  /// Darker shade for rims, pips on light faces and pressed states.
  Color get deepColor => Color.lerp(color, Colors.black, 0.28)!;

  /// Quieter variant for inactive seats.
  Color get mutedColor => Color.lerp(color, const Color(0xFF8A8A8A), 0.35)!;

  int get startIndex => switch (this) {
        LudoColor.red => 0,
        LudoColor.green => 13,
        LudoColor.yellow => 26,
        LudoColor.blue => 39,
      };
}

enum LudoDiceVisualState {
  disabled,
  waiting,
  ready,
  rolling,
  result,
}

class LudoBoardTokenView {
  const LudoBoardTokenView({
    required this.id,
    required this.color,
    required this.progress,
    required this.baseIndex,
    this.highlighted = false,
    this.emphasized = false,
    this.pending = false,
    this.finished = false,
    this.stackIndex = 0,
    this.stackCount = 1,
    this.onTap,
  });

  final String id;
  final LudoColor color;
  final int progress;
  final int baseIndex;
  final bool highlighted;
  final bool emphasized;
  final bool pending;
  final bool finished;
  final int stackIndex;
  final int stackCount;
  final VoidCallback? onTap;

  bool get isSelectable => onTap != null && highlighted;
}
