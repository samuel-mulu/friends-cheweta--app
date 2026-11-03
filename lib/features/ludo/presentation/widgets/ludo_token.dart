import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

/// Pawn-like Ludo token with optional legal-move halo.
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
  late final AnimationController _halo;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _syncHalo();
  }

  @override
  void didUpdateWidget(covariant LudoTokenPiece oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlighted != widget.highlighted) _syncHalo();
  }

  void _syncHalo() {
    if (widget.highlighted && !widget.pending) {
      _halo.repeat();
    } else {
      _halo.stop();
      _halo.value = 0;
    }
  }

  @override
  void dispose() {
    _halo.dispose();
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
            : widget.highlighted
                ? 1.06
                : _pressed
                    ? 0.94
                    : 1.0;

    return Semantics(
      button: selectable,
      enabled: selectable,
      label: label.toString(),
      child: GestureDetector(
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
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: AnimatedBuilder(
              animation: _halo,
              builder: (context, child) {
                return CustomPaint(
                  painter: _TokenPainter(
                    color: widget.color.color,
                    highlighted: widget.highlighted,
                    pending: widget.pending,
                    finished: widget.finished,
                    haloPhase: _halo.value,
                  ),
                  child: child,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenPainter extends CustomPainter {
  _TokenPainter({
    required this.color,
    required this.highlighted,
    required this.pending,
    required this.finished,
    required this.haloPhase,
  });

  final Color color;
  final bool highlighted;
  final bool pending;
  final bool finished;
  final double haloPhase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    if (highlighted || pending) {
      final pulse = 0.55 + 0.45 * math.sin(haloPhase * math.pi * 2);
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = pending ? 2.2 : 1.8
        ..color = (pending ? Colors.white : color).withValues(alpha: pending ? 0.95 : 0.35 + pulse * 0.45);
      final radius = w * (0.46 + (highlighted ? pulse * 0.04 : 0));
      _drawDashedCircle(canvas, Offset(cx, h * 0.52), radius, ringPaint, dash: highlighted && !pending);
    }

    // Soft ground shadow
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: finished ? 0.12 : 0.22)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.08);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h * 0.88), width: w * 0.55, height: h * 0.14),
      shadow,
    );

    final bodyTop = h * 0.38;
    final bodyBottom = h * 0.86;
    final neckY = h * 0.42;

    final bodyPath = Path()
      ..moveTo(cx - w * 0.16, neckY)
      ..quadraticBezierTo(cx - w * 0.34, bodyTop + h * 0.12, cx - w * 0.30, bodyBottom - h * 0.08)
      ..quadraticBezierTo(cx - w * 0.22, bodyBottom, cx, bodyBottom)
      ..quadraticBezierTo(cx + w * 0.22, bodyBottom, cx + w * 0.30, bodyBottom - h * 0.08)
      ..quadraticBezierTo(cx + w * 0.34, bodyTop + h * 0.12, cx + w * 0.16, neckY)
      ..close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(color, Colors.white, finished ? 0.22 : 0.12)!,
          color,
          Color.lerp(color, Colors.black, finished ? 0.18 : 0.22)!,
        ],
        stops: const [0, 0.45, 1],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(bodyPath, bodyPaint);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.04)
      ..color = Colors.white.withValues(alpha: finished ? 0.55 : 0.78);
    canvas.drawPath(bodyPath, rim);

    // Head
    final headCenter = Offset(cx, h * 0.28);
    final headRadius = w * 0.22;
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.05,
          colors: [
            Color.lerp(color, Colors.white, 0.35)!,
            color,
            Color.lerp(color, Colors.black, 0.2)!,
          ],
        ).createShader(Rect.fromCircle(center: headCenter, radius: headRadius)),
    );
    canvas.drawCircle(
      headCenter,
      headRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, w * 0.035)
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Specular highlight
    canvas.drawCircle(
      Offset(cx - w * 0.07, h * 0.22),
      w * 0.055,
      Paint()..color = Colors.white.withValues(alpha: finished ? 0.35 : 0.55),
    );

    if (finished) {
      canvas.drawCircle(
        headCenter,
        headRadius * 1.25,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.35),
      );
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint, {required bool dash}) {
    if (!dash) {
      canvas.drawCircle(center, radius, paint);
      return;
    }
    const segments = 28;
    const dashFraction = 0.55;
    final path = Path();
    for (var i = 0; i < segments; i++) {
      final start = (i / segments) * math.pi * 2;
      final end = start + (math.pi * 2 / segments) * dashFraction;
      path.addArc(Rect.fromCircle(center: center, radius: radius), start, end - start);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TokenPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.highlighted != highlighted ||
        oldDelegate.pending != pending ||
        oldDelegate.finished != finished ||
        oldDelegate.haloPhase != haloPhase;
  }
}
