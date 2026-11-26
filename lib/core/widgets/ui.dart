import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
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
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9, vertical: large ? 6 : 3),
      decoration: BoxDecoration(color: palette.moneyTint, borderRadius: BorderRadius.circular(999)),
      child: Text(
        '${prefix == null ? '' : '$prefix '}${MoneyFormatter.compactEtb(amountMinor)}',
        style: TextStyle(
          color: palette.money,
          fontWeight: FontWeight.w700,
          fontSize: large ? 14 : 12,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
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

/// Initials in a navy-tinted circle; a green ring marks a ready player.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({super.key, required this.name, this.size = 44, this.ready = false});
  final String name;
  final double size;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final initials = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).take(2).map((part) => part.characters.first.toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ready ? 2 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ready ? Border.all(color: palette.live, width: 2) : null,
      ),
      child: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: size * 0.34),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing, this.padding = const EdgeInsets.fromLTRB(0, 8, 0, 12)});
  final String title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ]),
      );
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
            strokeWidth: 4,
            strokeCap: StrokeCap.round,
            backgroundColor: AppPalette.of(context).surfaceAlt,
            color: urgent ? scheme.error : scheme.primary,
          ),
        ),
        Text(
          seconds >= 60 ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}' : '$seconds',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: widget.size * (seconds >= 60 ? 0.24 : 0.3),
            color: urgent ? scheme.error : scheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ]),
    );
  }
}
