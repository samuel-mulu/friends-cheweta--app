import 'package:flutter/material.dart';

/// Friends ጨዋታ palette: a card table at night.
///
/// Flat dark surfaces with hairline borders; one gold for the main action and
/// for money; green only for live/ready; red only for errors and destructive
/// actions. Game colours live on the game art, never on the chrome.
abstract final class AppColors {
  // The table (dark, the default).
  static const night = Color(0xFF0B1120);
  static const table = Color(0xFF131B2E);
  static const raised = Color(0xFF1B2540);
  static const line = Color(0xFF2A3655);
  static const ink = Color(0xFFEEF1F8);
  static const inkSoft = Color(0xFFC8D0E4);
  static const muted = Color(0xFF93A0BE);
  static const faint = Color(0xFF5F6C8C);

  // Gold: chips, money and the one main action per screen.
  static const gold = Color(0xFFF4B740);

  /// Text and icons on a gold fill.
  static const onGold = Color(0xFF1A1205);

  /// Gold that stays readable as text on a light surface.
  static const goldInk = Color(0xFF8A5A00);

  /// Selected gold tint on the dark table.
  static const goldWash = Color(0xFF2A2312);
  static const goldTint = Color(0xFFFFF1D2);

  static const live = Color(0xFF2BB673);
  static const liveSoft = Color(0xFF4FD394);
  static const liveTint = Color(0xFFE2F5EA);
  static const liveWash = Color(0xFF12291F);
  static const danger = Color(0xFFE5484D);
  static const dangerSoft = Color(0xFFFF7A7E);

  /// Behind sheets and the drawer.
  static const scrim = Color(0xB805080F);

  // Light (optional; the table stays the brand).
  static const lightBackground = Color(0xFFF2F4F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFE9EDF4);
  static const lightText = Color(0xFF0B1120);
  static const lightMuted = Color(0xFF55627F);
  static const lightBorder = Color(0xFFD9DFEA);

  // Dark aliases (older call sites).
  static const darkBackground = night;
  static const darkSurface = table;
  static const darkSurfaceAlt = raised;
  static const darkText = ink;
  static const darkMuted = muted;
  static const darkBorder = line;

  /// @deprecated brand names kept for older call sites.
  static const navy = night;
  static const navyRaised = raised;
  static const indigo = Color(0xFF1C2C6E);
  static const darkPrimary = gold;
  static const brand = night;
  static const brandDark = gold;
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
    required this.background,
    required this.selected,
  });

  /// Second surface level: chips, inset panels, skeletons.
  final Color surfaceAlt;
  final Color border;

  /// Money text (gold that reads on this background).
  final Color money;
  final Color moneyTint;
  final Color live;
  final Color liveTint;

  /// The page behind cards (insets on a card use it too).
  final Color background;

  /// Fill of a selected chip or card (with a gold border).
  final Color selected;

  static const light = AppPalette(
    surfaceAlt: AppColors.lightSurfaceAlt,
    border: AppColors.lightBorder,
    money: AppColors.goldInk,
    moneyTint: AppColors.goldTint,
    live: Color(0xFF16885A),
    liveTint: AppColors.liveTint,
    background: AppColors.lightBackground,
    selected: AppColors.goldTint,
  );

  static const dark = AppPalette(
    surfaceAlt: AppColors.raised,
    border: AppColors.line,
    money: AppColors.gold,
    moneyTint: AppColors.goldWash,
    live: AppColors.liveSoft,
    liveTint: AppColors.liveWash,
    background: AppColors.night,
    selected: AppColors.goldWash,
  );

  static AppPalette of(BuildContext context) => Theme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Color? surfaceAlt,
    Color? border,
    Color? money,
    Color? moneyTint,
    Color? live,
    Color? liveTint,
    Color? background,
    Color? selected,
  }) =>
      AppPalette(
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        money: money ?? this.money,
        moneyTint: moneyTint ?? this.moneyTint,
        live: live ?? this.live,
        liveTint: liveTint ?? this.liveTint,
        background: background ?? this.background,
        selected: selected ?? this.selected,
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
      background: Color.lerp(background, other.background, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
    );
  }
}
