import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';

/// Shared building blocks of the app's screens (not of the game boards).

/// A stake or prize amount. Gold means money, everywhere in the app.
class StakePill extends StatelessWidget {
  const StakePill({super.key, required this.amountMinor, this.prefix, this.large = false});
  final int amountMinor;
  final String? prefix;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 5 : 2),
      decoration: BoxDecoration(color: palette.moneyTint, borderRadius: BorderRadius.circular(999)),
      child: Text.rich(
        TextSpan(children: [
          if (prefix != null) TextSpan(text: '$prefix ', style: AppType.ui(size: large ? 13 : 11.5, weight: FontWeight.w600, color: palette.money)),
          TextSpan(text: MoneyFormatter.compactEtb(amountMinor)),
        ]),
        style: AppType.money(size: large ? 17 : 14.5, color: palette.money),
      ),
    );
  }
}

/// Small coloured status: "Ready", "Live", "In a game"…
enum StatusTone { live, neutral, muted }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = StatusTone.neutral, this.dot = false});
  final String label;
  final StatusTone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      StatusTone.live => (palette.liveTint, palette.live),
      StatusTone.neutral => (palette.surfaceAlt, scheme.onSurface),
      StatusTone.muted => (palette.surfaceAlt, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[LiveDot(color: fg, size: 6), const SizedBox(width: 5)],
        Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class LiveDot extends StatelessWidget {
  const LiveDot({super.key, this.color, this.size = 8});
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color ?? AppPalette.of(context).live, shape: BoxShape.circle),
      );
}

/// Initials on a flat disc; a green dot marks a ready (or online) player.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.name, this.size = 44, this.ready = false, this.ring = false});
  final String name;
  final double size;
  final bool ready;

  /// A gold ring (me, in the sidebar).
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final initials = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2).map((part) => part.characters.first.toUpperCase()).join();
    final dot = size * 0.26;
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            shape: BoxShape.circle,
            border: ring ? Border.all(color: AppColors.gold, width: 1.5) : null,
          ),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: AppType.display(size: size * 0.38, color: scheme.onSurface, height: size * 0.38),
          ),
        ),
        if (ready)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: palette.live,
                shape: BoxShape.circle,
                border: Border.all(color: palette.background, width: 2),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A section title in the condensed display face.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing, this.padding = const EdgeInsets.fromLTRB(0, 8, 0, 10)});
  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(title, style: AppType.display(size: 21, color: Theme.of(context).colorScheme.onSurface))),
          if (trailing != null) trailing!,
        ]),
      );
}

/// A flat panel: the card surface with a hairline border.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.radius = 16, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: AppPalette.of(context).border),
    );
    return Material(
      color: color ?? Theme.of(context).colorScheme.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? Padding(padding: padding, child: child) : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Title row of a sheet: condensed title, optional line under it.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: theme.textTheme.headlineSmall)),
          if (trailing != null) trailing!,
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14, height: 20 / 14)),
        ],
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppPalette.of(context).surfaceAlt, shape: BoxShape.circle),
          child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleSmall),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(message!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Placeholder block while content loads (keeps the layout from jumping).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 12});
  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.of(context).surfaceAlt;
    return FadeTransition(
      opacity: Tween(begin: 0.55, end: 1.0).animate(_pulse),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(widget.radius)),
      ),
    );
  }
}

/// A standard sheet: rounded, drag handle, safe area, scroll-aware.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: builder(sheetContext),
      ),
    ),
  );
}

/// Seconds left until [expiresAt], drawn as a ring that empties.
class CountdownRing extends StatefulWidget {
  const CountdownRing({super.key, required this.expiresAt, required this.total, this.size = 64});
  final DateTime expiresAt;
  final Duration total;
  final double size;

  @override
  State<CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<CountdownRing> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expiresAt.difference(DateTime.now().toUtc());
    final seconds = math.max(0, left.inMilliseconds / 1000).ceil();
    final fraction = widget.total.inMilliseconds == 0 ? 0.0 : (left.inMilliseconds / widget.total.inMilliseconds).clamp(0.0, 1.0);
    final scheme = Theme.of(context).colorScheme;
    final urgent = seconds <= 5;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: fraction,
            strokeWidth: 3.5,
            strokeCap: StrokeCap.round,
            backgroundColor: AppPalette.of(context).surfaceAlt,
            color: urgent ? scheme.error : AppColors.gold,
          ),
        ),
        Text(
          seconds >= 60 ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}' : '$seconds',
          style: AppType.money(size: widget.size * (seconds >= 60 ? 0.28 : 0.36), color: urgent ? scheme.error : scheme.onSurface),
        ),
      ]),
    );
  }
}
