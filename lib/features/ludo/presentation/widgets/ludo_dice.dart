import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

class LudoDice extends StatefulWidget {
  const LudoDice({
    super.key,
    required this.value,
    required this.animateKey,
    this.enabled = false,
    this.onTap,
    this.accentColor,
    this.label,
    this.compact = false,
  });

  final int? value;
  final int animateKey;
  final bool enabled;
  final VoidCallback? onTap;
  final LudoColor? accentColor;
  final String? label;
  final bool compact;

  @override
  State<LudoDice> createState() => _LudoDiceState();
}

class _LudoDiceState extends State<LudoDice> {
  Timer? _timer;
  int _shown = 1;

  @override
  void initState() {
    super.initState();
    _shown = widget.value ?? 1;
  }

  @override
  void didUpdateWidget(covariant LudoDice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animateKey != widget.animateKey && widget.value != null) {
      _animateTo(widget.value!);
    }
    if (widget.value == null) {
      setState(() => _shown = 1);
    } else if (oldWidget.value != widget.value && oldWidget.animateKey == widget.animateKey) {
      _shown = widget.value!;
    }
  }

  void _animateTo(int target) {
    _timer?.cancel();
    var ticks = 0;
    final random = Random();
    _timer = Timer.periodic(const Duration(milliseconds: 75), (timer) {
      ticks += 1;
      if (!mounted) return;
      setState(() => _shown = ticks >= 7 ? target : random.nextInt(6) + 1);
      if (ticks >= 7) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor?.color ??
        (widget.enabled ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant);
    final size = widget.compact ? 58.0 : 74.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
        ],
        Semantics(
          button: widget.enabled,
          label: widget.enabled ? 'Roll ${widget.label ?? 'dice'}' : '${widget.label ?? 'Dice'} $_shown',
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.enabled ? widget.onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: widget.accentColor != null
                    ? accent.withValues(alpha: widget.enabled ? 0.18 : 0.1)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: accent.withValues(alpha: widget.enabled ? 0.85 : 0.45),
                  width: widget.enabled ? 2.4 : 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: widget.enabled ? 0.28 : 0.12),
                    blurRadius: widget.enabled ? 14 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.value == null ? '–' : '$_shown',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: accent,
                        fontSize: widget.compact ? 22 : null,
                      ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
