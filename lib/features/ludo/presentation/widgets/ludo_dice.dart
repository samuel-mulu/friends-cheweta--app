import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

/// Visual die with pip faces. The face it settles on is always the
/// server-provided [value]; spinning before that is presentation only.
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
    this.spinning = false,
  });

  /// Authoritative face from the server (or null before any roll).
  final int? value;

  /// Increases when a new server roll for this die's owner is presented.
  /// Only an increase animates, so other players' rolls never move this die.
  final int animateKey;

  /// True from the owner's tap until the server result is presented: the die
  /// spins at once instead of waiting for the network round trip.
  final bool spinning;

  final LudoDiceVisualState state;
  final VoidCallback? onTap;
  final LudoColor? accentColor;
  final double size;
  final bool showRollHint;

  @override
  State<LudoDice> createState() => _LudoDiceState();
}

class _LudoDiceState extends State<LudoDice> with TickerProviderStateMixin {
  static const _flipEvery = Duration(milliseconds: 70);

  late final AnimationController _pulse;
  late final AnimationController _roll;
  int _shown = 1;
  bool _rolling = false;
  int? _settleTo;
  DateTime _lastFlip = DateTime.fromMillisecondsSinceEpoch(0);
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _shown = (widget.value ?? 1).clamp(1, 6);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _roll = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
    _roll.addListener(_onRollTick);
    _syncPulse();
    if (widget.spinning) _spin();
  }

  @override
  void didUpdateWidget(covariant LudoDice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();

    if (widget.animateKey > oldWidget.animateKey && widget.value != null) {
      _settle(widget.value!);
    } else if (widget.spinning && !oldWidget.spinning) {
      _spin();
    } else if (!widget.spinning && oldWidget.spinning && _settleTo == null) {
      // The roll was rejected or failed: stop and keep the last real face.
      _roll.stop();
      setState(() {
        _rolling = false;
        _shown = (widget.value ?? 1).clamp(1, 6);
      });
    } else if (!_rolling && widget.value != oldWidget.value) {
      setState(() => _shown = (widget.value ?? 1).clamp(1, 6));
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

  void _spin() {
    _rolling = true;
    _settleTo = null;
    _roll.repeat();
  }

  void _settle(int target) {
    // Finish just inside the queue's dice slot so the face lands before the next event.
    _roll.duration = LudoMotion.diceRoll - const Duration(milliseconds: 30);
    _rolling = true;
    _settleTo = target.clamp(1, 6);
    _roll
      ..stop()
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _shown = _settleTo ?? _shown;
          _settleTo = null;
          _rolling = false;
        });
      });
  }

  void _onRollTick() {
    if (!_rolling || !mounted) return;
    final settleTo = _settleTo;
    if (settleTo != null && _roll.value >= 0.8) {
      if (_shown != settleTo) setState(() => _shown = settleTo);
      return;
    }
    final now = DateTime.now();
    if (now.difference(_lastFlip) < _flipEvery) return;
    _lastFlip = now;
    setState(() => _shown = _rng.nextInt(6) + 1);
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
    final color = widget.accentColor ?? LudoColor.green;
    final effective = _effectiveState;
    final face = widget.value == null && !_rolling ? null : _shown;
    final dimmed = effective == LudoDiceVisualState.disabled || effective == LudoDiceVisualState.waiting;

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
          child: GestureDetector(
            onTap: _enabled ? widget.onTap : null,
            child: AnimatedBuilder(
              animation: Listenable.merge([_pulse, _roll]),
              builder: (context, child) {
                final size = widget.size;
                double dy = 0, angle = 0, sx = 1, sy = 1;
                if (_rolling) {
                  final t = _roll.value;
                  if (_settleTo == null) {
                    // Waiting for the server: continuous tumble in place.
                    dy = -(math.sin(t * math.pi * 2).abs()) * size * 0.18;
                    angle = t * math.pi * 2;
                  } else {
                    // Settle: hop, ~1.5 turns easing out, squash on landing.
                    final eased = Curves.easeOutCubic.transform(t);
                    dy = -math.sin(math.pi * math.min(t / 0.8, 1)) * size * 0.35;
                    angle = eased * math.pi * 3;
                    if (t > 0.8) {
                      final k = math.sin((t - 0.8) / 0.2 * math.pi);
                      sy = 1 - 0.14 * k;
                      sx = 1 + 0.1 * k;
                    }
                  }
                } else if (effective == LudoDiceVisualState.ready) {
                  dy = -_pulse.value * size * 0.06;
                }
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(sx, sy, 1),
                    child: Transform.rotate(angle: angle, child: child),
                  ),
                );
              },
              child: _DiceFace(
                value: face,
                size: widget.size,
                color: color,
                glow: effective == LudoDiceVisualState.ready,
                dimmed: dimmed,
              ),
            ),
          ),
        ),
        if (widget.showRollHint && effective == LudoDiceVisualState.ready) ...[
          const SizedBox(height: 4),
          Text(
            'TAP TO ROLL',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ],
    );
  }
}

/// Player-colored die body with white pips.
class _DiceFace extends StatelessWidget {
  const _DiceFace({required this.value, required this.size, required this.color, this.glow = false, this.dimmed = false});

  final int? value;
  final double size;
  final LudoColor color;
  final bool glow;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final body = dimmed ? color.mutedColor : color.color;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: dimmed ? 0.7 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(body, Colors.white, 0.28)!, body, Color.lerp(body, Colors.black, 0.25)!],
            stops: const [0, 0.5, 1],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: glow ? 0.95 : 0.5), width: glow ? 2.4 : 1.4),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: size * 0.16, offset: Offset(0, size * 0.08)),
            if (glow) BoxShadow(color: body.withValues(alpha: 0.75), blurRadius: size * 0.4, spreadRadius: size * 0.04),
          ],
        ),
        child: value == null
            ? null
            : CustomPaint(painter: _PipPainter(value: value!.clamp(1, 6), color: Colors.white), size: Size.square(size)),
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
    4: [Alignment(-0.45, -0.45), Alignment(0.45, -0.45), Alignment(-0.45, 0.45), Alignment(0.45, 0.45)],
    5: [Alignment(-0.45, -0.45), Alignment(0.45, -0.45), Alignment.center, Alignment(-0.45, 0.45), Alignment(0.45, 0.45)],
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
    final radius = size.shortestSide * (value == 1 ? 0.12 : 0.085);
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.25);
    final paint = Paint()..color = color;
    for (final align in _positions[value] ?? _positions[1]!) {
      final offset = Offset((align.x + 1) / 2 * size.width, (align.y + 1) / 2 * size.height);
      canvas.drawCircle(offset + Offset(0, radius * 0.25), radius, shade);
      canvas.drawCircle(offset, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter oldDelegate) => oldDelegate.value != value || oldDelegate.color != color;
}

/// Static face (roll history chips, tests).
class LudoDiceFace extends StatelessWidget {
  const LudoDiceFace({super.key, required this.value, this.size = 36, this.color = LudoColor.green});

  final int value;
  final double size;
  final LudoColor color;

  @override
  Widget build(BuildContext context) => _DiceFace(value: value.clamp(1, 6), size: size, color: color);
}
