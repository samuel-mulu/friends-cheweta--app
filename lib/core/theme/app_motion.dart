import 'package:flutter/animation.dart';

/// How fast the app answers. Motion only answers what the player did;
/// nothing loops while they wait (celebration is kept for winning).
abstract final class AppMotion {
  /// Press feedback.
  static const tap = Duration(milliseconds: 100);

  /// Selection, tabs, switching content.
  static const state = Duration(milliseconds: 180);

  /// Sheets, the drawer, larger layout changes.
  static const sheet = Duration(milliseconds: 260);

  static const curve = Curves.easeOutCubic;
}
