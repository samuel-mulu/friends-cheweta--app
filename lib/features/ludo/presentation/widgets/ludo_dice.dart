import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
    this.settleDuration = const Duration(milliseconds: 650),
    this.onSettled,
  });

  /// How long the settle tumble takes (the timeline's dice scene length).
  final Duration settleDuration;

  /// The settle animation finished and the authoritative face is showing.
  final VoidCallback? onSettled;

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
    _roll
      ..stop()
      ..duration = const Duration(milliseconds: 620)
      ..repeat();
  }

  void _settle(int target) {
    // Finish just inside the scene so the face lands before the next event.
    final settle = widget.settleDuration - const Duration(milliseconds: 30);
    _roll.duration = settle < const Duration(milliseconds: 120) ? const Duration(milliseconds: 120) : settle;
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
        widget.onSettled?.call();
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
                double dy = 0, zoom = 1, spinX = 0, spinY = 0, spinZ = 0, sx = 1, sy = 1;
                if (_rolling) {
                  final t = _roll.value;
                  if (_settleTo == null) {
                    // Waiting for the server: lifted and zoomed in, spinning with a
                    // 3D wobble (kept under ~35 degrees so the cube never turns edge-on).
                    zoom = 1.35 + 0.05 * math.sin(t * math.pi * 4);
                    dy = -size * 0.22;
                    spinX = 0.55 * math.sin(t * math.pi * 4);
                    spinY = 0.55 * math.cos(t * math.pi * 6);
                    spinZ = t * math.pi * 2;
                  } else {
                    // Settle: zoom up, tumble about 1.5 turns easing out, land with a bounce.
                    final up = math.sin(math.pi * math.min(t / 0.8, 1));
                    final eased = Curves.easeOutCubic.transform(math.min(t / 0.8, 1));
                    zoom = 1 + 0.4 * up;
                    dy = -up * size * 0.3;
                    final wobble = 1 - eased;
                    spinX = 0.55 * wobble * math.sin(t * math.pi * 6);
                    spinY = 0.55 * wobble * math.cos(t * math.pi * 5);
                    spinZ = wobble * math.pi * 3;
                    if (t > 0.8) {
                      final k = math.sin((t - 0.8) / 0.2 * math.pi);
                      sy = 1 - 0.12 * k;
                      sx = 1 + 0.08 * k;
                    }
                  }
                } else if (effective == LudoDiceVisualState.ready) {
                  dy = -_pulse.value * size * 0.06;
                  zoom = 1 + _pulse.value * 0.04;
                }
                final tumble = Matrix4.identity()
                  ..setEntry(3, 2, 0.0016) // perspective
                  ..rotateX(spinX)
                  ..rotateY(spinY)
                  ..rotateZ(spinZ);
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transform: Matrix4.diagonal3Values(sx * zoom, sy * zoom, 1),
                    child: Transform(alignment: Alignment.center, transform: tumble, child: child),
                  ),
                );
              },
              // Flat face at rest; a 3D cube only while it rolls.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(animation), child: child),
                ),
                child: _rolling
                    ? _DiceCube(key: const ValueKey('cube'), value: face, size: widget.size, color: color)
                    : _DiceFace(
                        key: const ValueKey('face'),
                        value: face,
                        size: widget.size,
                        color: color,
                        glow: effective == LudoDiceVisualState.ready,
                        dimmed: dimmed,
                      ),
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

/// Flat player-colored face with white pips: the die at rest, and history chips.
class _DiceFace extends StatelessWidget {
  const _DiceFace({super.key, required this.value, required this.size, required this.color, this.glow = false, this.dimmed = false});

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

/// The die as a solid cube seen from above a corner: the result on top, two
/// neighbouring faces on the sides (as on a real die, opposite faces sum to 7).
class _DiceCube extends StatelessWidget {
  const _DiceCube({super.key, required this.value, required this.size, required this.color});

  final int? value;
  final double size;
  final LudoColor color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CubePainter(value: value ?? 1, body: color.color));
}

class _CubePainter extends CustomPainter {
  _CubePainter({required this.value, required this.body});

  final int? value;
  final Color body;

  /// Two faces next to [top] (never [top] or its opposite), for the sides.
  static (int, int) _sides(int top) => switch (top) {
        1 => (2, 3),
        2 => (3, 1),
        3 => (1, 2),
        4 => (5, 1),
        5 => (1, 3),
        _ => (5, 4),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Corners of the cube's silhouette (a hexagon) and the corner nearest the eye.
    final top = Offset(w * 0.5, h * 0.05);
    final upRight = Offset(w * 0.95, h * 0.29);
    final downRight = Offset(w * 0.95, h * 0.73);
    final bottom = Offset(w * 0.5, h * 0.97);
    final downLeft = Offset(w * 0.05, h * 0.73);
    final upLeft = Offset(w * 0.05, h * 0.29);
    final centre = Offset(w * 0.5, h * 0.53);

    // Soft ground shadow.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.5, h * 0.98), width: w * 0.8, height: h * 0.16),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05),
    );

    Path face(List<Offset> points) => Path()..addPolygon(points, true);
    final topFace = face([top, upRight, centre, upLeft]);
    final leftFace = face([upLeft, centre, bottom, downLeft]);
    final rightFace = face([centre, upRight, downRight, bottom]);

    // Rounded edges: one thick stroke in a darker body colour around the silhouette.
    canvas.drawPath(
      face([top, upRight, downRight, bottom, downLeft, upLeft]),
      Paint()
        ..color = Color.lerp(body, Colors.black, 0.3)!
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 0.09,
    );
    canvas.drawPath(topFace, Paint()..color = Color.lerp(body, Colors.white, 0.18)!);
    canvas.drawPath(leftFace, Paint()..color = body);
    canvas.drawPath(rightFace, Paint()..color = Color.lerp(body, Colors.black, 0.22)!);
    // Light catching the two upper edges.
    canvas.drawPath(
      Path()
        ..moveTo(upLeft.dx, upLeft.dy)
        ..lineTo(top.dx, top.dy)
        ..lineTo(upRight.dx, upRight.dy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = w * 0.025,
    );

    final shown = value;
    if (shown == null) return;
    final (left, right) = _sides(shown);
    _pips(canvas, shown, origin: upLeft, u: top - upLeft, v: centre - upLeft, alpha: 1);
    _pips(canvas, left, origin: upLeft, u: centre - upLeft, v: downLeft - upLeft, alpha: 0.85);
    _pips(canvas, right, origin: centre, u: upRight - centre, v: bottom - centre, alpha: 0.75);
  }

  /// Pips of [n] on the face spanned by [u] and [v] from [origin] (the unit square mapped onto it).
  void _pips(Canvas canvas, int n, {required Offset origin, required Offset u, required Offset v, required double alpha}) {
    canvas.save();
    canvas.transform(Float64List.fromList([u.dx, u.dy, 0, 0, v.dx, v.dy, 0, 0, 0, 0, 1, 0, origin.dx, origin.dy, 0, 1]));
    final radius = n == 1 ? 0.13 : 0.095;
    final white = Paint()..color = Colors.white.withValues(alpha: alpha);
    final shade = Paint()..color = Colors.black.withValues(alpha: 0.18 * alpha);
    for (final a in _PipPainter._positions[n]!) {
      final c = Offset(0.5 + a.x * 0.31, 0.5 + a.y * 0.31);
      canvas.drawCircle(c + const Offset(0.012, 0.02), radius, shade);
      canvas.drawCircle(c, radius, white);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CubePainter old) => old.value != value || old.body != body;
}
