import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';

extension DamaTypeIcon on DamaType {
  /// እግረኛ walks forward; ታንከኛ is armoured both ways.
  IconData get icon => switch (this) {
        DamaType.egregna => Icons.directions_walk_rounded,
        DamaType.tankegna => Icons.shield_rounded,
      };
}

/// The two Dama types side by side as big cards (icon, Amharic name, short
/// description). The chosen one is outlined in the brand colour.
class DamaTypePicker extends StatelessWidget {
  const DamaTypePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.readyCounts = const {},
    this.enabled = true,
    this.compact = false,
  });

  /// Null when nothing is chosen yet.
  final DamaType? selected;
  final ValueChanged<DamaType> onChanged;

  /// Players ready at each type (shown as a small live count).
  final Map<DamaType, int> readyCounts;
  final bool enabled;

  /// Shorter cards (bottom bar).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Dama type',
      child: Row(children: [
        for (final type in DamaType.values) ...[
          if (type != DamaType.values.first) const SizedBox(width: 10),
          Expanded(
            child: _TypeCard(
              type: type,
              selected: type == selected,
              ready: readyCounts[type] ?? 0,
              compact: compact,
              onTap: enabled
                  ? () {
                      if (type == selected) return;
                      HapticFeedback.selectionClick();
                      onChanged(type);
                    }
                  : null,
            ),
          ),
        ],
      ]),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.selected, required this.ready, required this.compact, this.onTap});
  final DamaType type;
  final bool selected;
  final int ready;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final accent = scheme.primary;
    final foreground = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      constraints: BoxConstraints(minHeight: compact ? 56 : 68),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.10) : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? accent : palette.border, width: selected ? 2 : 1),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(type.icon, size: compact ? 18 : 20, color: selected ? accent : foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  type.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: compact ? 15 : 17, fontWeight: FontWeight.w800, color: foreground),
                ),
              ),
            ]),
            const SizedBox(height: 3),
            Text(
              type.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
        if (ready > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              LiveDot(size: 6, color: palette.live),
              const SizedBox(width: 3),
              Text('$ready', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: palette.live)),
            ]),
          ),
      ]),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: '${type.name}, ${type.captureRule}${ready > 0 ? ' $ready ready' : ''}',
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null && !selected ? 0.55 : 1,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: card),
        ),
      ),
    );
  }
}

/// Small type label for rows, sheets and the match header.
class DamaTypeTag extends StatelessWidget {
  const DamaTypeTag({super.key, required this.type, this.emphasized = false, this.large = false});
  final DamaType type;

  /// Outlined in the brand colour (e.g. a different type than mine).
  final bool emphasized;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final color = emphasized ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      label: '${type.name}, ${type.captureRule}',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 5 : 2),
        decoration: BoxDecoration(
          color: emphasized ? scheme.primary.withValues(alpha: 0.10) : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: emphasized ? Border.all(color: scheme.primary.withValues(alpha: 0.6)) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(type.icon, size: large ? 15 : 12, color: color),
          const SizedBox(width: 4),
          Text(type.name, style: TextStyle(fontSize: large ? 13.5 : 11.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }
}
