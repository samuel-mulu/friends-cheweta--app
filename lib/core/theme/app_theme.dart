import 'package:flutter/material.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_radius.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primaryText = dark ? AppColors.darkText : AppColors.lightText;
    final mutedText = dark ? AppColors.darkMuted : AppColors.lightMuted;
    final borderColor = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final surfaceColor = dark ? AppColors.darkSurface : AppColors.lightSurface;

    final scheme = ColorScheme.fromSeed(
      seedColor: dark ? AppColors.brandDark : AppColors.brand,
      brightness: brightness,
      surface: surfaceColor,
    ).copyWith(
      onSurface: primaryText,
      onSurfaceVariant: mutedText,
    );

    TextStyle textStyle({
      required double fontSize,
      required double height,
      required FontWeight fontWeight,
      Color? color,
    }) =>
        GoogleFonts.inter(
          fontSize: fontSize,
          height: height,
          fontWeight: fontWeight,
          color: color ?? primaryText,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? AppColors.darkBackground : AppColors.lightBackground,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: primaryText,
      displayColor: primaryText,
    ).copyWith(
      displaySmall: textStyle(fontSize: 32, height: 38 / 32, fontWeight: FontWeight.w700),
      headlineMedium: textStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w700),
      headlineSmall: textStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700),
      titleLarge: textStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w600),
      titleMedium: textStyle(fontSize: 17, height: 23 / 17, fontWeight: FontWeight.w600),
      bodyLarge: textStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w400),
      bodyMedium: textStyle(fontSize: 14, height: 1.5, fontWeight: FontWeight.w400),
      bodySmall: textStyle(fontSize: 12, height: 1.5, fontWeight: FontWeight.w400, color: mutedText),
      labelLarge: textStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600),
      labelSmall: textStyle(fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w500, color: mutedText),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.darkBackground : AppColors.lightBackground,
        foregroundColor: primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        labelStyle: TextStyle(color: mutedText),
        hintStyle: TextStyle(color: mutedText),
        prefixIconColor: mutedText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.medium), borderSide: BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.medium), borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.medium), borderSide: BorderSide(color: scheme.primary, width: 1.4)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large), side: BorderSide(color: borderColor)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        backgroundColor: surfaceColor,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textStyle(
            fontSize: 12,
            height: 1.2,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : mutedText,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? scheme.primary : mutedText);
        }),
      ),
    );
  }
}
