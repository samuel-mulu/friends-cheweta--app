import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typefaces: Barlow for reading, Barlow Condensed for titles, stakes and
/// money (the scoreboard voice), Noto Sans Ethiopic for Amharic.
abstract final class AppType {
  static const _figures = [FontFeature.tabularFigures()];

  /// Body and UI text.
  static TextStyle ui({double size = 14, FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
      GoogleFonts.barlow(fontSize: size, fontWeight: weight, color: color, height: height == null ? null : height / size);

  /// Titles and big labels (condensed, bold).
  static TextStyle display({double size = 24, FontWeight weight = FontWeight.w700, Color? color, double? height}) =>
      GoogleFonts.barlowCondensed(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height == null ? 1.1 : height / size,
        letterSpacing: 0.2,
      );

  /// Amounts: condensed with even figures so numbers don't jump.
  static TextStyle money({double size = 18, FontWeight weight = FontWeight.w700, Color? color}) =>
      display(size: size, weight: weight, color: color).copyWith(fontFeatures: _figures);

  /// Amharic (Ethiopic script) text.
  static TextStyle amharic({double size = 14, FontWeight weight = FontWeight.w700, Color? color}) =>
      GoogleFonts.notoSansEthiopic(fontSize: size, fontWeight: weight, color: color, height: 1.25);
}
