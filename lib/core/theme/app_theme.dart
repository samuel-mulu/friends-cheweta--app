import 'package:flutter/material.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_motion.dart';
import 'package:friends_game_app/core/theme/app_radius.dart';
import 'package:google_fonts/google_fonts.dart';

/// Friends ጨዋታ theme. Dark (the table) is the brand; light is an option.
///
/// One gold filled button per screen carries the main action; everything else
/// is outlined or plain. Surfaces are flat with hairline borders (no gradients,
/// no glow, no tinted elevation).
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final text = dark ? AppColors.ink : AppColors.lightText;
    final muted = dark ? AppColors.muted : AppColors.lightMuted;
    final border = dark ? AppColors.line : AppColors.lightBorder;
    final surface = dark ? AppColors.table : AppColors.lightSurface;
    final surfaceAlt = dark ? AppColors.raised : AppColors.lightSurfaceAlt;
    final background = dark ? AppColors.night : AppColors.lightBackground;
    // Gold reads on the dark table; on light it darkens to stay legible as text.
    final primary = dark ? AppColors.gold : AppColors.goldInk;
    final onPrimary = dark ? AppColors.onGold : Colors.white;
    final palette = dark ? AppPalette.dark : AppPalette.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: palette.selected,
      onPrimaryContainer: primary,
      secondary: AppColors.gold,
      onSecondary: AppColors.onGold,
      secondaryContainer: palette.moneyTint,
      onSecondaryContainer: palette.money,
      tertiary: palette.live,
      onTertiary: dark ? AppColors.night : Colors.white,
      error: dark ? AppColors.dangerSoft : AppColors.danger,
      onError: Colors.white,
      errorContainer: dark ? const Color(0xFF3A1518) : const Color(0xFFFBE6E6),
      onErrorContainer: dark ? const Color(0xFFFFB4B6) : AppColors.danger,
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
      inverseSurface: dark ? AppColors.ink : AppColors.night,
      onInverseSurface: dark ? AppColors.night : AppColors.ink,
      inversePrimary: AppColors.gold,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );

    TextStyle ui(double size, double height, FontWeight weight, [Color? color]) => GoogleFonts.barlow(
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          color: color ?? text,
        );
    TextStyle display(double size, double height, [Color? color]) => GoogleFonts.barlowCondensed(
          fontSize: size,
          height: height / size,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: color ?? text,
        );

    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme);
    final textTheme = GoogleFonts.barlowTextTheme(base.textTheme).apply(bodyColor: text, displayColor: text).copyWith(
          displaySmall: display(40, 44),
          headlineLarge: display(34, 38),
          headlineMedium: display(30, 34),
          headlineSmall: display(26, 30),
          titleLarge: display(23, 28),
          titleMedium: ui(16, 22, FontWeight.w600),
          titleSmall: ui(14.5, 20, FontWeight.w600),
          bodyLarge: ui(16, 24, FontWeight.w400),
          bodyMedium: ui(15, 21, FontWeight.w400),
          bodySmall: ui(13, 18, FontWeight.w400, muted),
          labelLarge: ui(16, 20, FontWeight.w700),
          labelMedium: ui(13.5, 18, FontWeight.w600),
          labelSmall: ui(12, 16, FontWeight.w500, muted),
        );

    final shape14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    const buttonSize = Size(64, 52);
    final goldText = dark ? AppColors.gold : AppColors.goldInk;

    return base.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      extensions: [palette],
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 4,
        titleTextStyle: display(24, 28),
        iconTheme: IconThemeData(color: text),
        actionsIconTheme: IconThemeData(color: dark ? AppColors.inkSoft : muted),
      ),
      // The main action: gold, in both modes.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.onGold,
          disabledBackgroundColor: surfaceAlt,
          disabledForegroundColor: dark ? AppColors.faint : muted,
          minimumSize: buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: shape14,
          elevation: 0,
          textStyle: ui(16, 20, FontWeight.w700),
          animationDuration: AppMotion.tap,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: shape14,
          foregroundColor: text,
          side: BorderSide(color: border, width: 1.5),
          textStyle: ui(16, 20, FontWeight.w600),
          animationDuration: AppMotion.tap,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: goldText,
          textStyle: ui(15, 20, FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: buttonSize,
          backgroundColor: surfaceAlt,
          foregroundColor: text,
          shape: shape14,
          textStyle: ui(16, 20, FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.onGold,
        elevation: 0,
        highlightElevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        titleTextStyle: ui(15.5, 21, FontWeight.w600),
        subtitleTextStyle: ui(13.5, 19, FontWeight.w400, muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minVerticalPadding: 10,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: palette.selected,
        disabledColor: surfaceAlt,
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const BorderSide(color: AppColors.gold, width: 1.5)
              : BorderSide(color: border),
        ),
        labelStyle: ui(14, 18, FontWeight.w600),
        secondaryLabelStyle: ui(14, 18, FontWeight.w700, goldText),
        checkmarkColor: goldText,
        showCheckmark: false,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: AppColors.scrim,
        showDragHandle: true,
        dragHandleColor: border,
        dragHandleSize: const Size(40, 4),
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: AppColors.scrim,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: border)),
        titleTextStyle: display(24, 28),
        contentTextStyle: ui(15, 22, FontWeight.w400, muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? AppColors.raised : AppColors.night,
        contentTextStyle: ui(14.5, 20, FontWeight.w500, AppColors.ink),
        actionTextColor: AppColors.gold,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: dark ? const BorderSide(color: AppColors.line) : BorderSide.none,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        scrimColor: AppColors.scrim,
        elevation: 0,
        width: 304,
        shape: Border(right: BorderSide(color: border)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: ui(15, 20, FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: border)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surfaceAlt),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        ),
      ),
      dividerTheme: DividerThemeData(color: dark ? AppColors.raised : border, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.gold,
        linearTrackColor: surfaceAlt,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.onGold : (dark ? AppColors.muted : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.gold : surfaceAlt,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.gold : border,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? goldText : muted),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.gold : null),
        checkColor: const WidgetStatePropertyAll(AppColors.onGold),
        side: BorderSide(color: border, width: 1.5),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: muted,
        indicatorColor: AppColors.gold,
        dividerColor: border,
        labelStyle: ui(15, 20, FontWeight.w600),
        unselectedLabelStyle: ui(15, 20, FontWeight.w500),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.gold,
        selectionColor: AppColors.gold.withValues(alpha: 0.3),
        selectionHandleColor: AppColors.gold,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? AppColors.table : surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: TextStyle(color: goldText),
        hintStyle: TextStyle(color: dark ? AppColors.faint : muted),
        helperStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: muted,
          selectedBackgroundColor: palette.selected,
          selectedForegroundColor: goldText,
          side: BorderSide(color: border),
          textStyle: ui(14.5, 20, FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 68,
        backgroundColor: surface,
        indicatorColor: palette.selected,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return ui(12, 16, selected ? FontWeight.w600 : FontWeight.w500, selected ? goldText : muted);
        }),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(color: states.contains(WidgetState.selected) ? goldText : muted),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: dark ? AppColors.raised : AppColors.night, borderRadius: BorderRadius.circular(8)),
        textStyle: ui(13, 18, FontWeight.w500, AppColors.ink),
      ),
    );
  }
}
