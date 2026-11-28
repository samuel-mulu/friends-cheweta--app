import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_motion.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/match/presentation/widgets/crown_icon.dart';

extension GameVariantIcon on GameVariant {
  IconData get icon => switch (rulesVersion) {
        'DAMA_ET_FORWARD_V1' => Icons.directions_walk_rounded,
        'DAMA_ET_V1' => Icons.shield_rounded,
        'LUDO_CLASSIC_V3' => Icons.undo_rounded,
        'LUDO_NO_CAPTURE_V1' => Icons.handshake_rounded,
        'LUDO_MISSED_CAPTURE_V1' => Icons.warning_amber_rounded,
        'KARTA_LATLAT_V1' => Icons.style_rounded,
        'KARTA_TABLE_V1' => Icons.table_restaurant_rounded,
        _ => Icons.sports_esports_rounded,
      };
}

/// A game's types side by side as cards (icon, Amharic name, short
/// description). The chosen one is outlined in gold. Two or three per row.
class VariantPicker extends StatelessWidget {
  const VariantPicker({
    super.key,
    required this.variants,
    required this.selected,
    required this.onChanged,
    this.readyCounts = const {},
    this.enabled = true,
    this.compact = false,
  });

  final List<GameVariant> variants;

  /// Null when nothing is chosen yet.
  final GameVariant? selected;
  final ValueChanged<GameVariant> onChanged;

  /// Players ready at each type (shown as a small live count).
  final Map<GameVariant, int> readyCounts;
  final bool enabled;

  /// Shorter cards (bottom panel).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Equal-height cards. IntrinsicHeight bounds the stretch: in a Column (the
    // lobby's bottom panel, the practice sheet) the height is unbounded, and a
    // bare stretch Row throws there ("forces an infinite height").
    return Semantics(
      label: 'Game type',
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (index, variant) in variants.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _VariantCard(
              variant: variant,
              selected: variant == selected,
              ready: readyCounts[variant] ?? 0,
              compact: compact,
              dense: variants.length > 2,
              onTap: enabled
                  ? () {
                      if (variant == selected) return;
                      HapticFeedback.selectionClick();
                      onChanged(variant);
                    }
                  : null,
            ),
          ),
        ],
        ]),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.selected,
    required this.ready,
    required this.compact,
    required this.dense,
    this.onTap,
  });
  final GameVariant variant;
  final bool selected;
  final int ready;
  final bool compact;

  /// Three across: smaller type, the name may take two lines.
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final accent = scheme.primary;
    final foreground = selected ? accent : scheme.onSurface;
    final nameSize = dense ? 13.5 : (compact ? 16.0 : 18.0);
    final card = AnimatedContainer(
      duration: AppMotion.state,
      curve: AppMotion.curve,
      constraints: BoxConstraints(minHeight: compact ? 58 : 68),
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: selected ? palette.selected : palette.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppColors.gold : palette.border, width: selected ? 1.5 : 1),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(variant.icon, size: dense ? 15 : (compact ? 17 : 19), color: selected ? accent : scheme.onSurfaceVariant),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  variant.name,
                  maxLines: dense ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppType.amharic(size: nameSize, color: foreground),
                ),
              ),
            ]),
            if (!dense) ...[
              const SizedBox(height: 2),
              Text(
                variant.hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppType.amharic(size: compact ? 11.5 : 12.5, weight: FontWeight.w500, color: scheme.onSurfaceVariant),
              ),
            ],
          ]),
        ),
        if (ready > 0)
          Positioned(
            top: -4,
            right: -2,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              LiveDot(size: 6, color: palette.live),
              const SizedBox(width: 3),
              Text('$ready', style: AppType.ui(size: 12, weight: FontWeight.w700, color: palette.live)),
            ]),
          ),
      ]),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: '${variant.name}, ${variant.rule}${ready > 0 ? ' $ready ready' : ''}',
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null && !selected ? 0.55 : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: card),
        ),
      ),
    );
  }
}

/// Small type badge for rows, sheets and match headers.
class VariantTag extends StatelessWidget {
  const VariantTag({super.key, required this.variant, this.emphasized = false, this.large = false});
  final GameVariant variant;

  /// Outlined in gold (e.g. a different type than mine).
  final bool emphasized;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final color = emphasized ? scheme.primary : scheme.onSurface.withValues(alpha: 0.82);
    return Semantics(
      label: '${variant.name}, ${variant.rule}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 4 : 1),
        decoration: BoxDecoration(
          color: emphasized ? palette.selected : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: emphasized ? Border.all(color: AppColors.gold.withValues(alpha: 0.55)) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(variant.icon, size: large ? 15 : 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              variant.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.amharic(size: large ? 14 : 12, color: color),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ludo goal: first to 1, 2, 3 or 4 tokens home, as crowns. The chosen one is gold.
class GoalChips extends StatelessWidget {
  const GoalChips({super.key, required this.selected, required this.onChanged, this.enabled = true});
  final int selected;
  final ValueChanged<int> onChanged;
  final bool enabled;

  static String label(int goal) => goal == 4 ? 'All 4 home' : 'First to $goal home';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Tokens to win',
      child: Row(children: [
        for (var goal = 1; goal <= 4; goal++) ...[
          if (goal > 1) const SizedBox(width: 8),
          Expanded(
            flex: goal == 4 ? 4 : 3,
            child: Semantics(
              button: true,
              selected: goal == selected,
              label: label(goal),
              excludeSemantics: true,
              child: Material(
                color: goal == selected ? palette.selected : palette.surfaceAlt,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: goal == selected ? AppColors.gold : palette.border, width: goal == selected ? 1.5 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: enabled && goal != selected
                      ? () {
                          HapticFeedback.selectionClick();
                          onChanged(goal);
                        }
                      : null,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: CrownRow(
                        count: goal,
                        size: 15,
                        spacing: 1,
                        filled: goal == selected ? goal : 0,
                        emptyColor: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// How many play: 2 (1v1), 3 or 4, as a row of chips (people icons). For a
/// Karta table it is the number of seats. Shows how many wait at each size.
class PlayerCountChips extends StatelessWidget {
  const PlayerCountChips({
    super.key,
    required this.counts,
    required this.selected,
    required this.onChanged,
    this.readyCounts = const {},
    this.enabled = true,
    this.seats = false,
  });
  final List<int> counts;
  final int selected;
  final ValueChanged<int> onChanged;
  final Map<int, int> readyCounts;
  final bool enabled;

  /// A Karta table: "Up to N at the table".
  final bool seats;

  static String label(int count, {bool seats = false}) =>
      seats ? 'Up to $count at the table' : (count == 2 ? '1 v 1' : '$count players');

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: seats ? 'Seats at the table' : 'Players',
      child: Row(children: [
        for (final count in counts) ...[
          if (count != counts.first) const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              selected: count == selected,
              label: '${label(count, seats: seats)}${(readyCounts[count] ?? 0) > 0 ? ', ${readyCounts[count]} ready' : ''}',
              excludeSemantics: true,
              child: Material(
                color: count == selected ? palette.selected : palette.surfaceAlt,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: count == selected ? AppColors.gold : palette.border, width: count == selected ? 1.5 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: enabled && count != selected
                      ? () {
                          HapticFeedback.selectionClick();
                          onChanged(count);
                        }
                      : null,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 44),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          count == 2 ? Icons.people_alt_rounded : Icons.groups_rounded,
                          size: 18,
                          color: count == selected ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          count == 2 && !seats ? '1v1' : '$count',
                          style: AppType.ui(
                            size: 15,
                            weight: FontWeight.w700,
                            color: count == selected ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                        if ((readyCounts[count] ?? 0) > 0) ...[
                          const SizedBox(width: 6),
                          LiveDot(size: 6, color: palette.live),
                          const SizedBox(width: 3),
                          Text('${readyCounts[count]}', style: AppType.ui(size: 12, weight: FontWeight.w700, color: palette.live)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// "4p" next to a stake or a player: a 3–4 player table (or Karta table seats).
class PlayersTag extends StatelessWidget {
  const PlayersTag({super.key, required this.count, this.table = false});
  final int count;
  final bool table;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    return Semantics(
      label: table ? 'Table of $count' : '$count players',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: palette.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(table ? Icons.table_restaurant_rounded : Icons.groups_rounded, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text('$count', style: AppType.ui(size: 12, weight: FontWeight.w700, color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// The types of [gameCode] and what each changes (a game's "How to play" when
/// its rules sheet is only about the types).
Future<void> showGameTypes(BuildContext context, String gameCode) => showAppSheet<void>(
      context,
      builder: (context) {
        final theme = Theme.of(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHeader(title: 'Game types', subtitle: 'Each stake is one type. Only what is listed differs.'),
          for (final variant in GameVariants.of(gameCode))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(variant.icon, color: theme.colorScheme.primary),
              title: Text('${variant.name}  ·  ${variant.hint}', style: AppType.amharic(size: 15, color: theme.colorScheme.onSurface)),
              subtitle: Text(variant.rule),
            ),
        ]);
      },
    );

/// A player's Ludo goal as a row of small crowns (for lobby rows).
class GoalCrowns extends StatelessWidget {
  const GoalCrowns({super.key, required this.goal, this.size = 12});
  final int goal;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: GoalChips.label(goal),
        excludeSemantics: true,
        child: CrownRow(count: goal, size: size, spacing: 1),
      );
}
