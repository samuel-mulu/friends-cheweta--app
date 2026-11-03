import 'package:flutter/material.dart';

enum LudoColor { red, green, yellow, blue }

extension LudoColorX on LudoColor {
  /// Refined classic Ludo palette — game colors, not app theme colors.
  Color get color => switch (this) {
        LudoColor.red => const Color(0xFFC44536),
        LudoColor.green => const Color(0xFF2A9D5C),
        LudoColor.yellow => const Color(0xFFD4A017),
        LudoColor.blue => const Color(0xFF2F6FBF),
      };

  /// Slightly quieter variant for inactive 1v1 chrome.
  Color get mutedColor => Color.lerp(color, const Color(0xFF8A8A8A), 0.28)!;

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
