import 'package:flutter/material.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_radius.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final text = dark ? AppColors.darkText : AppColors.lightText;
    final muted = dark ? AppColors.darkMuted : AppColors.lightMuted;
    final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
    final surfaceAlt = dark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt;
    final background = dark ? AppColors.darkBackground : AppColors.lightBackground;
    final primary = dark ? AppColors.darkPrimary : AppColors.navy;
    final onPrimary = dark ? AppColors.navy : Colors.white;

    // An explicit scheme (not seeded) so every colour is a deliberate one.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: dark ? AppColors.navyRaised : const Color(0xFFE3E8F4),
      onPrimaryContainer: dark ? AppColors.darkText : AppColors.navy,
      secondary: AppColors.gold,
      onSecondary: AppColors.navy,
      secondaryContainer: dark ? const Color(0xFF2E2710) : AppColors.goldTint,
      onSecondaryContainer: dark ? AppColors.gold : AppColors.goldInk,
      tertiary: AppColors.live,
      onTertiary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: dark ? const Color(0xFF3A1515) : const Color(0xFFFBE6E6),
      onErrorContainer: dark ? const Color(0xFFFFB4AB) : AppColors.danger,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: muted,
      surfaceContainerLowest: background,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceAlt,
      surfaceContainerHigh: surfaceAlt,
      surfaceContainerHighest: surfaceAlt,
      outline: border,
      outlineVariant: border,
      inverseSurface: dark ? AppColors.darkText : AppColors.navy,
      onInverseSurface: dark ? AppColors.navy : Colors.white,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    TextStyle style(double size, double height, FontWeight weight, [Color? color]) => GoogleFonts.inter(
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          color: color ?? text,
          letterSpacing: size >= 20 ? -0.3 : 0,
        );

    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: text, displayColor: text)
        .copyWith(
          headlineMedium: style(26, 32, FontWeight.w700),
          headlineSmall: style(22, 28, FontWeight.w700),
          titleLarge: style(19, 25, FontWeight.w700),
          titleMedium: style(16, 22, FontWeight.w600),
          titleSmall: style(14, 20, FontWeight.w600),
          bodyLarge: style(16, 24, FontWeight.w400),
          bodyMedium: style(14, 20, FontWeight.w400),
          bodySmall: style(12.5, 18, FontWeight.w400, muted),
          labelLarge: style(15, 20, FontWeight.w600),
          labelMedium: style(13, 18, FontWeight.w600),
          labelSmall: style(11.5, 16, FontWeight.w500, muted),
        );

    final shape14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonSize = Size(64, 48);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      extensions: [dark ? AppPalette.dark : AppPalette.light],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle: style(18, 24, FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: shape14,
          textStyle: style(15, 20, FontWeight.w600),
          disabledBackgroundColor: surfaceAlt,
          disabledForegroundColor: muted,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: shape14,
          foregroundColor: text,
          side: BorderSide(color: border, width: 1.2),
          textStyle: style(15, 20, FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: primary,
          textStyle: style(14, 20, FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: style(15, 20, FontWeight.w600),
        subtitleTextStyle: style(13, 18, FontWeight.w400, muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary,
        side: BorderSide(color: border),
        labelStyle: style(13.5, 18, FontWeight.w600),
        secondaryLabelStyle: style(13.5, 18, FontWeight.w600, onPrimary),
        checkmarkColor: onPrimary,
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: style(19, 25, FontWeight.w700),
        contentTextStyle: style(14.5, 21, FontWeight.w400, muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? AppColors.darkSurfaceAlt : AppColors.navy,
        contentTextStyle: style(14, 20, FontWeight.w500, Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: surfaceAlt),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: primary, width: 1.5)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: primary,
          selectedForegroundColor: onPrimary,
          side: BorderSide(color: border),
          textStyle: style(14, 20, FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return style(12, 16, selected ? FontWeight.w600 : FontWeight.w500, selected ? primary : muted);
        }),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? primary : muted),
        ),
      ),
    );
  }
}
