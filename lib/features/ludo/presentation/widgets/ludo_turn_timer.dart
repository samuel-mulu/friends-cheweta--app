import 'dart:async';
import 'package:flutter/material.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Isolated countdown so tick rebuilds do not repaint the board.
class LudoTurnTimer extends ConsumerStatefulWidget {
  const LudoTurnTimer({
    super.key,
    required this.turnEndsAt,
    this.estimated = false,
    this.compact = false,
  });

  final DateTime? turnEndsAt;
  final bool estimated;
  final bool compact;

  @override
  ConsumerState<LudoTurnTimer> createState() => _LudoTurnTimerState();
}

class _LudoTurnTimerState extends ConsumerState<LudoTurnTimer> {
  Timer? _ticker;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _tick();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant LudoTurnTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnEndsAt != widget.turnEndsAt) _tick();
  }

  void _tick() {
    final deadline = widget.turnEndsAt;
    if (deadline == null) {
      if (_remaining != null && mounted) setState(() => _remaining = null);
      return;
    }
    final now = ref.read(gameSocketServiceProvider).serverNow();
    final next = deadline.difference(now);
    final clamped = next.isNegative ? Duration.zero : next;
    if (clamped.inSeconds != _remaining?.inSeconds && mounted) {
      setState(() => _remaining = clamped);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secs = _remaining?.inSeconds;
    if (secs == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final urgent = secs <= 5;
    final label = '${secs}s${widget.estimated ? ' ~' : ''}';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 8 : 10,
        vertical: widget.compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: urgent ? scheme.errorContainer.withValues(alpha: 0.85) : scheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: urgent ? scheme.error.withValues(alpha: 0.45) : scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: urgent ? scheme.onErrorContainer : scheme.onSurface,
            ),
      ),
    );
  }
}
