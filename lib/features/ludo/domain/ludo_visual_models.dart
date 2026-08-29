import 'package:flutter/material.dart';

enum LudoColor { red, green, yellow, blue }

extension LudoColorX on LudoColor {
  Color get color => switch (this) {
        LudoColor.red => const Color(0xFFD84A4A),
        LudoColor.green => const Color(0xFF2E9D68),
        LudoColor.yellow => const Color(0xFFE6B938),
        LudoColor.blue => const Color(0xFF3D79C7),
      };

  int get startIndex => switch (this) {
        LudoColor.red => 0,
        LudoColor.green => 13,
        LudoColor.yellow => 26,
        LudoColor.blue => 39,
      };
}

class LudoBoardTokenView {
  const LudoBoardTokenView({
    required this.id,
    required this.color,
    required this.progress,
    required this.baseIndex,
    this.highlighted = false,
    this.emphasized = false,
    this.stackIndex = 0,
    this.onTap,
  });

  final String id;
  final LudoColor color;
  final int progress;
  final int baseIndex;
  final bool highlighted;
  final bool emphasized;
  final int stackIndex;
  final VoidCallback? onTap;
}
