import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

/// Map-pin style token: white pin, colored core, dark outline. Readable on
/// both colored yards and white track cells. Movable tokens bob and show a
/// pulsing ring on the cell so "what can I tap" is obvious at a glance.
class LudoTokenPiece extends StatefulWidget {
  const LudoTokenPiece({
    super.key,
    required this.color,
    required this.size,
    required this.baseIndex,
    this.highlighted = false,
    this.emphasized = false,
    this.pending = false,
    this.finished = false,
    this.onTap,
  });

  final LudoColor color;
  final double size;
  final int baseIndex;
  final bool highlighted;
  final bool emphasized;
  final bool pending;
  final bool finished;
  final VoidCallback? onTap;

  @override
  State<LudoTokenPiece> createState() => _LudoTokenPieceState();
}

class _LudoTokenPieceState extends State<LudoTokenPiece> with SingleTickerProviderStateMixin {
  late final AnimationController _bob;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _sync();
  }

  @override
  void didUpdateWidget(covariant LudoTokenPiece oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlighted != widget.highlighted || oldWidget.pending != widget.pending) _sync();
  }

  void _sync() {
    if (widget.highlighted && !widget.pending) {
      _bob.repeat();
    } else {
      _bob
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectable = widget.onTap != null && widget.highlighted;
    final label = StringBuffer('${widget.color.name} token ${widget.baseIndex + 1}');
    if (widget.finished) {
      label.write(', finished');
    } else if (widget.pending) {
      label.write(', move pending');
    } else if (selectable) {
      label.write(', legal move');
    } else {
      label.write(', not selectable');
    }

    final scale = widget.emphasized
        ? 1.18
        : widget.pending
            ? 1.08
            : _pressed
                ? 0.92
                : 1.0;

    return Semantics(
      button: selectable,
      enabled: selectable,
      label: label.toString(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: selectable ? (_) => setState(() => _pressed = true) : null,
        onTapUp: selectable
            ? (_) {
                setState(() => _pressed = false);
                widget.onTap?.call();
              }
            : null,
        onTapCancel: selectable ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _bob,
              builder: (context, _) => CustomPaint(
                painter: _PinPainter(
                  color: widget.color,
                  highlighted: widget.highlighted,
                  pending: widget.pending,
                  finished: widget.finished,
                  phase: _bob.value,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({
    required this.color,
    required this.highlighted,
    required this.pending,
    required this.finished,
    required this.phase,
  });

  final LudoColor color;
  final bool highlighted;
  final bool pending;
  final bool finished;
  final double phase;

  static const _outline = Color(0xFF16202E);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final wave = math.sin(phase * math.pi * 2);
    final lift = highlighted && !pending ? (0.5 + 0.5 * wave) * h * 0.1 : 0.0;
    final tip = Offset(w / 2, h * 0.9);

    // Cell ring under movable tokens.
    if (highlighted || pending) {
      final glow = 0.45 + 0.35 * (0.5 + 0.5 * wave);
      canvas.drawOval(
        Rect.fromCenter(center: tip, width: w * 0.86, height: h * 0.32),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.07
          ..color = (pending ? Colors.white : color.color).withValues(alpha: glow),
      );
    }

    // Ground shadow shrinks as the pin lifts.
    canvas.drawOval(
      Rect.fromCenter(center: tip, width: w * (0.5 - lift / h), height: h * 0.14),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05),
    );

    canvas.save();
    canvas.translate(0, -lift);
    final headCenter = Offset(w / 2, h * 0.38);
    final r = w * 0.32;
    // Teardrop: head circle blended into a point at the tip.
    final pin = Path()
      ..moveTo(tip.dx, tip.dy - h * 0.02)
      ..quadraticBezierTo(headCenter.dx - r * 1.05, headCenter.dy + r * 0.9, headCenter.dx - r, headCenter.dy)
      ..arcToPoint(Offset(headCenter.dx + r, headCenter.dy), radius: Radius.circular(r))
      ..quadraticBezierTo(headCenter.dx + r * 1.05, headCenter.dy + r * 0.9, tip.dx, tip.dy - h * 0.02)
      ..close();
    canvas.drawPath(pin, Paint()..color = Colors.white);
    canvas.drawPath(
      pin,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.06)
        ..color = _outline,
    );

    // Colored core with a soft highlight.
    final core = r * 0.62;
    canvas.drawCircle(
      headCenter,
      core,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Color.lerp(color.color, Colors.white, 0.3)!, color.color, color.deepColor],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: headCenter, radius: core)),
    );
    if (finished) {
      canvas.drawPath(_star(headCenter, core * 0.7, core * 0.3), Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  Path _star(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(radius * math.cos(a), radius * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _PinPainter old) =>
      old.color != color ||
      old.highlighted != highlighted ||
      old.pending != pending ||
      old.finished != finished ||
      old.phase != phase;
}
