import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

/// Visual die with pip faces. Final face always equals the server-provided [value].
class LudoDice extends StatefulWidget {
  const LudoDice({
    super.key,
    required this.value,
    required this.animateKey,
    this.state = LudoDiceVisualState.waiting,
    this.onTap,
    this.accentColor,
    this.size = 64,
    this.showRollHint = true,
  });

  /// Authoritative face from the server (or null before any roll).
  final int? value;

  /// Bumps when a new server dice presentation should animate.
  final int animateKey;

  final LudoDiceVisualState state;
  final VoidCallback? onTap;
  final LudoColor? accentColor;
  final double size;
  final bool showRollHint;

  @override
  State<LudoDice> createState() => _LudoDiceState();
}

class _LudoDiceState extends State<LudoDice> with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _roll;
  int _shown = 1;
  bool _rolling = false;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _shown = (widget.value ?? 1).clamp(1, 6);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _roll = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _roll.addListener(_onRollTick);
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant LudoDice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();

    if (oldWidget.animateKey != widget.animateKey && widget.value != null) {
      _animateToServerValue(widget.value!);
      return;
    }

    if (widget.value == null) {
      setState(() {
        _shown = 1;
        _rolling = false;
      });
    } else if (oldWidget.value != widget.value && oldWidget.animateKey == widget.animateKey) {
      setState(() {
        _shown = widget.value!.clamp(1, 6);
        _rolling = false;
      });
    }
  }

  void _syncPulse() {
    if (widget.state == LudoDiceVisualState.ready) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  void _animateToServerValue(int target) {
    final clamped = target.clamp(1, 6);
    _rolling = true;
    _roll.stop();
    _roll
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _shown = clamped;
          _rolling = false;
        });
      });
  }

  void _onRollTick() {
    if (!_rolling || !mounted) return;
    // Presentation-only flicker; final face is forced to server value on complete.
    if (_roll.value < 0.85) {
      setState(() => _shown = _rng.nextInt(6) + 1);
    } else if (widget.value != null) {
      setState(() => _shown = widget.value!.clamp(1, 6));
    }
  }

  @override
  void dispose() {
    _roll.removeListener(_onRollTick);
    _pulse.dispose();
    _roll.dispose();
    super.dispose();
  }

  bool get _enabled => widget.state == LudoDiceVisualState.ready && widget.onTap != null && !_rolling;

  LudoDiceVisualState get _effectiveState {
    if (_rolling) return LudoDiceVisualState.rolling;
    if (widget.state == LudoDiceVisualState.ready) return LudoDiceVisualState.ready;
    if (widget.value != null) return LudoDiceVisualState.result;
    return widget.state;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor?.color ?? Theme.of(context).colorScheme.primary;
    final effective = _effectiveState;
    final face = widget.value == null && !_rolling ? null : _shown;

    final semanticsLabel = switch (effective) {
      LudoDiceVisualState.ready => 'Roll dice',
      LudoDiceVisualState.rolling => 'Dice rolling',
      LudoDiceVisualState.result => 'Dice result ${face ?? widget.value}',
      LudoDiceVisualState.waiting => 'Dice waiting',
      LudoDiceVisualState.disabled => 'Dice disabled',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: _enabled,
          enabled: _enabled,
          label: semanticsLabel,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _roll]),
            builder: (context, child) {
              final lift = effective == LudoDiceVisualState.ready ? 1.0 + (_pulse.value * 0.04) : 1.0;
              final tilt = _rolling ? math.sin(_roll.value * math.pi * 6) * 0.08 : 0.0;
              return Transform.scale(
                scale: lift,
                child: Transform.rotate(
                  angle: tilt,
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _enabled ? widget.onTap : null,
                borderRadius: BorderRadius.circular(widget.size * 0.22),
                child: _DiceFace(
                  value: face,
                  size: widget.size,
                  accent: accent,
                  emphasized: effective == LudoDiceVisualState.ready || effective == LudoDiceVisualState.rolling,
                  muted: effective == LudoDiceVisualState.disabled || effective == LudoDiceVisualState.waiting,
                ),
              ),
            ),
          ),
        ),
        if (widget.showRollHint && effective == LudoDiceVisualState.ready) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_upward_rounded, size: 14, color: accent),
              const SizedBox(width: 2),
              Text(
                'Roll',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DiceFace extends StatelessWidget {
  const _DiceFace({
    required this.value,
    required this.size,
    required this.accent,
    required this.emphasized,
    required this.muted,
  });

  final int? value;
  final double size;
  final Color accent;
  final bool emphasized;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faceColor = muted
        ? (isDark ? const Color(0xFFE8E4DC) : const Color(0xFFF7F4EE)).withValues(alpha: 0.72)
        : (isDark ? const Color(0xFFF3EFE6) : const Color(0xFFFFFCF7));
    final pipColor = muted ? const Color(0xFF5A5A5A).withValues(alpha: 0.55) : const Color(0xFF1F1F1F);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(faceColor, Colors.white, 0.35)!,
            faceColor,
            Color.lerp(faceColor, const Color(0xFFD8D2C8), 0.35)!,
          ],
        ),
        border: Border.all(
          color: accent.withValues(alpha: emphasized ? 0.85 : 0.35),
          width: emphasized ? 2.2 : 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: emphasized ? 0.22 : 0.12),
            blurRadius: emphasized ? 14 : 8,
            offset: Offset(0, emphasized ? 5 : 3),
          ),
          if (emphasized)
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 12,
              spreadRadius: 0.5,
            ),
        ],
      ),
      child: value == null
          ? Center(
              child: Text(
                '–',
                style: TextStyle(
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w700,
                  color: pipColor.withValues(alpha: 0.45),
                ),
              ),
            )
          : CustomPaint(
              painter: _PipPainter(value: value!.clamp(1, 6), color: pipColor),
              size: Size.square(size),
            ),
    );
  }
}

class _PipPainter extends CustomPainter {
  _PipPainter({required this.value, required this.color});

  final int value;
  final Color color;

  static const _positions = <int, List<Alignment>>{
    1: [Alignment.center],
    2: [Alignment(-0.45, -0.45), Alignment(0.45, 0.45)],
    3: [Alignment(-0.45, -0.45), Alignment.center, Alignment(0.45, 0.45)],
    4: [
      Alignment(-0.45, -0.45),
      Alignment(0.45, -0.45),
      Alignment(-0.45, 0.45),
      Alignment(0.45, 0.45),
    ],
    5: [
      Alignment(-0.45, -0.45),
      Alignment(0.45, -0.45),
      Alignment.center,
      Alignment(-0.45, 0.45),
      Alignment(0.45, 0.45),
    ],
    6: [
      Alignment(-0.45, -0.5),
      Alignment(0.45, -0.5),
      Alignment(-0.45, 0),
      Alignment(0.45, 0),
      Alignment(-0.45, 0.5),
      Alignment(0.45, 0.5),
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final radius = size.shortestSide * 0.085;
    final spots = _positions[value] ?? _positions[1]!;
    for (final align in spots) {
      final offset = Offset(
        (align.x + 1) / 2 * size.width,
        (align.y + 1) / 2 * size.height,
      );
      canvas.drawCircle(offset, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

/// Renders a static pip face for tests / start-roll chips without animation.
class LudoDiceFace extends StatelessWidget {
  const LudoDiceFace({super.key, required this.value, this.size = 36, this.accent});

  final int value;
  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return _DiceFace(
      value: value.clamp(1, 6),
      size: size,
      accent: accent ?? Theme.of(context).colorScheme.outline,
      emphasized: false,
      muted: false,
    );
  }
}
