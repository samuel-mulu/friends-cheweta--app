import 'package:flutter/material.dart';

/// Brand palette, taken from the Friends logo (navy tile, gold ring).
///
/// Roles, so colour always means the same thing:
/// - navy: the brand and every primary action;
/// - gold: money and winning only (balances, stakes, prizes, "1st");
/// - green: live and ready only;
/// - red: errors and destructive actions.
abstract final class AppColors {
  // Brand.
  static const navy = Color(0xFF0B1530);
  static const navyRaised = Color(0xFF15224A);
  static const indigo = Color(0xFF1C2C6E);
  static const gold = Color(0xFFFFC83D);

  /// Gold that stays readable as text on a light surface.
  static const goldInk = Color(0xFF9A6A00);
  static const goldTint = Color(0xFFFFF4D6);

  static const live = Color(0xFF1C9A5B);
  static const liveTint = Color(0xFFE2F5EA);
  static const danger = Color(0xFFC63C3C);

  // Light.
  static const lightBackground = Color(0xFFF4F6FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFEDF0F6);
  static const lightText = Color(0xFF0B1530);
  static const lightMuted = Color(0xFF5B6580);
  static const lightBorder = Color(0xFFE0E5EE);

  // Dark: the same navy family, lifted.
  static const darkBackground = Color(0xFF070E21);
  static const darkSurface = Color(0xFF0F1A33);
  static const darkSurfaceAlt = Color(0xFF172443);
  static const darkText = Color(0xFFEEF2F8);
  static const darkMuted = Color(0xFF97A2BB);
  static const darkBorder = Color(0xFF223156);
  static const darkPrimary = Color(0xFFDCE4F7);

  /// @deprecated names kept for older call sites.
  static const brand = navy;
  static const brandDark = darkPrimary;
}

/// Colours that depend on light/dark, for widgets outside the Material scheme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.surfaceAlt,
    required this.border,
    required this.money,
    required this.moneyTint,
    required this.live,
    required this.liveTint,
  });

  /// Second surface level: chips, inset panels, skeletons.
  final Color surfaceAlt;
  final Color border;

  /// Money text (gold that reads on this background).
  final Color money;
  final Color moneyTint;
  final Color live;
  final Color liveTint;

  static const light = AppPalette(
    surfaceAlt: AppColors.lightSurfaceAlt,
    border: AppColors.lightBorder,
    money: AppColors.goldInk,
    moneyTint: AppColors.goldTint,
    live: AppColors.live,
    liveTint: AppColors.liveTint,
  );

  static const dark = AppPalette(
    surfaceAlt: AppColors.darkSurfaceAlt,
    border: AppColors.darkBorder,
    money: AppColors.gold,
    moneyTint: Color(0xFF2E2710),
    live: Color(0xFF3CC47E),
    liveTint: Color(0xFF12301F),
  );

  static AppPalette of(BuildContext context) => Theme.of(context).extension<AppPalette>() ?? light;

  @override
  AppPalette copyWith({Color? surfaceAlt, Color? border, Color? money, Color? moneyTint, Color? live, Color? liveTint}) =>
      AppPalette(
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        money: money ?? this.money,
        moneyTint: moneyTint ?? this.moneyTint,
        live: live ?? this.live,
        liveTint: liveTint ?? this.liveTint,
      );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      money: Color.lerp(money, other.money, t)!,
      moneyTint: Color.lerp(moneyTint, other.moneyTint, t)!,
      live: Color.lerp(live, other.live, t)!,
      liveTint: Color.lerp(liveTint, other.liveTint, t)!,
    );
  }
}
