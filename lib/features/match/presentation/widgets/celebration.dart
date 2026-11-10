import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/features/match/presentation/widgets/crown_icon.dart';

enum ConfettiStyle {
  /// Pops outward from the centre and falls (a token reaching home).
  burst,

  /// Falls from the top across the whole area (a win).
  rain,
}

/// Lightweight confetti: one controller, seeded particles, one painter. Plays
/// once when inserted; give it a new key to play again. Never takes touches.
class Confetti extends StatefulWidget {
  const Confetti({
    super.key,
    this.style = ConfettiStyle.burst,
    this.seed = 1,
    this.count = 36,
    this.duration = const Duration(milliseconds: 1300),
    this.colors = _defaultColors,
  });

  final ConfettiStyle style;
  final int seed;
  final int count;
  final Duration duration;
  final List<Color> colors;

  static const _defaultColors = [
    Color(0xFFFFC83D),
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Colors.white,
  ];

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration)..forward();
  late final List<_Particle> _particles = _Particle.generate(widget);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _ConfettiPainter(_particles, widget.style, _controller),
          ),
        ),
      );
}

class _Particle {
  const _Particle(this.angle, this.speed, this.x, this.spin, this.size, this.color, this.delay);
  final double angle; // burst direction / rain sway phase
  final double speed; // 0..1
  final double x; // rain start (fraction of width)
  final double spin;
  final double size; // fraction of the area's short side
  final Color color;
  final double delay; // 0..0.3 of the timeline

  static List<_Particle> generate(Confetti config) {
    final random = math.Random(config.seed);
    return [
      for (var i = 0; i < config.count; i++)
        _Particle(
          random.nextDouble() * math.pi * 2,
          0.55 + random.nextDouble() * 0.45,
          random.nextDouble(),
          (random.nextDouble() - 0.5) * 12,
          0.025 + random.nextDouble() * 0.025,
          config.colors[i % config.colors.length],
          config.style == ConfettiStyle.rain ? random.nextDouble() * 0.3 : 0,
        ),
    ];
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.style, this.progress) : super(repaint: progress);
  final List<_Particle> particles;
  final ConfettiStyle style;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final short = size.shortestSide;
    final paint = Paint();
    for (final p in particles) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final Offset position;
      if (style == ConfettiStyle.burst) {
        final reach = short * 0.5 * p.speed * Curves.easeOut.transform(local);
        final fall = short * 0.35 * local * local; // gravity
        position = size.center(Offset.zero) + Offset(math.cos(p.angle) * reach, math.sin(p.angle) * reach + fall);
      } else {
        final sway = math.sin(p.angle + local * math.pi * 3) * short * 0.04;
        position = Offset(p.x * size.width + sway, -short * 0.05 + local * (size.height * 1.1) * p.speed);
      }
      final fade = local > 0.75 ? (1 - local) / 0.25 : 1.0;
      paint.color = p.color.withValues(alpha: fade.clamp(0.0, 1.0));
      final w = short * p.size;
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(p.spin * local);
      // Flat ribbons that "flip" as they fall.
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.45 * (0.3 + 0.7 * math.cos(p.spin * local * 2).abs())),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.particles != particles || old.style != style;
}

/// Full-screen "You won!" moment: confetti rain, a big crown and the result
/// line. Tap anywhere to dismiss.
class WinCelebration extends StatelessWidget {
  const WinCelebration({super.key, required this.title, required this.subtitle, required this.onDismiss});
  final String title;
  final String subtitle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black.withValues(alpha: 0.45)),
            const Confetti(style: ConfettiStyle.rain, count: 90, seed: 7, duration: Duration(milliseconds: 2600)),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 520),
                curve: Curves.elasticOut,
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CrownIcon(size: 96),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14)),
                ]),
              ),
            ),
          ],
        ),
      );
}
