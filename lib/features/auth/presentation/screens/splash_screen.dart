import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/app/router.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';

/// Brand intro while the session is restored.
///
/// The intro (~1.3 s) plays once; the router leaves this screen when both the
/// intro is done and the session is known (usually instant). If start-up takes
/// longer, a loader with an honest status line appears, and Retry when the
/// server cannot be reached — never an endless spinner.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  Timer? _slowTimer;

  /// Seconds spent waiting after the intro (drives the status line).
  int _waited = 0;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) _introDone();
    });
  }

  /// Lets the router leave once the session is known; starts the wait clock.
  void _introDone() {
    if (_slowTimer != null) return;
    ref.read(splashIntroDoneProvider.notifier).state = true;
    _slowTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _waited++);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_intro.isAnimating || _intro.isCompleted) return;
    // Respect "remove animations": skip straight to the end.
    if (MediaQuery.of(context).disableAnimations) {
      // After the first frame: providers must not change while building.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _intro.value = 1; // completes → _introDone
      });
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  double _part(double start, double end, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_intro.value - start) / (end - start)).clamp(0.0, 1.0).toDouble());

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final failed = auth.error != null && !auth.loading;

    return Scaffold(
      backgroundColor: BrandColors.navy,
      body: Stack(fit: StackFit.expand, children: [
        RepaintBoundary(child: CustomPaint(painter: _GlowBackdrop(_ambient))),
        SafeArea(
          child: AnimatedBuilder(
            animation: _intro,
            builder: (context, _) {
              final mark = _part(0, 0.75);
              final word = _part(0.45, 0.9);
              final tagline = _part(0.65, 1);
              return Column(children: [
                const Spacer(flex: 5),
                Transform.scale(
                  scale: 0.82 + 0.18 * _part(0, 0.6, Curves.easeOutBack),
                  child: Opacity(
                    opacity: _part(0, 0.2),
                    child: _GlowingMark(reveal: _intro.value, glow: mark),
                  ),
                ),
                const SizedBox(height: 28),
                Opacity(
                  opacity: word,
                  child: Transform.translate(
                    offset: Offset(0, 14 * (1 - word)),
                    child: Text(
                      'FRIENDS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        // Letters close in as they arrive.
                        letterSpacing: 4 + 10 * (1 - word),
                        height: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: tagline,
                  child: const Text(
                    'GAME HUB',
                    style: TextStyle(color: BrandColors.gold, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 6, height: 1),
                  ),
                ),
                const Spacer(flex: 4),
                SizedBox(
                  height: 120,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: failed
                        ? _RetryPanel(
                            key: const ValueKey('retry'),
                            message: auth.error!,
                            onRetry: () {
                              setState(() => _waited = 0);
                              ref.read(authControllerProvider.notifier).restoreSession();
                            },
                          )
                        : _intro.isCompleted
                            ? _Waiting(key: const ValueKey('wait'), seconds: _waited, ambient: _ambient)
                            : const SizedBox.shrink(),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

/// The mark with a soft gold halo that blooms as it is drawn.
class _GlowingMark extends StatelessWidget {
  const _GlowingMark({required this.reveal, required this.glow});
  final double reveal;
  final double glow;
  static const _size = 112.0;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_size * 0.26), // same corners as the tile
          boxShadow: [
            BoxShadow(color: BrandColors.gold.withValues(alpha: 0.18 * glow), blurRadius: 44),
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 22, offset: const Offset(0, 10)),
          ],
        ),
        child: AppLogoMark(size: _size, reveal: reveal),
      );
}

/// Three dots in the game colors, plus what is happening when it takes long.
class _Waiting extends StatelessWidget {
  const _Waiting({super.key, required this.seconds, required this.ambient});
  final int seconds;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    // Shown only when start-up is slower than the intro.
    final status = seconds < 2
        ? ''
        : seconds < 6
            ? 'Connecting…'
            : 'Waking up the server, almost there…';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _BouncingDots(animation: ambient),
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          status,
          key: ValueKey(status),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    ]);
  }
}

class _BouncingDots extends StatelessWidget {
  const _BouncingDots({required this.animation});
  final Animation<double> animation;
  static const _colors = [BrandColors.red, BrandColors.gold, BrandColors.green];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          // The ambient controller spans 9 s; one bounce cycle every 0.9 s.
          final cycle = (animation.value * 10) % 1;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Transform.translate(
                  offset: Offset(0, -7 * math.max(0, math.sin((cycle - i * 0.15) * 2 * math.pi))),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: _colors[i], shape: BoxShape.circle),
                  ),
                ),
              ),
          ]);
        },
      );
}

class _RetryPanel extends StatelessWidget {
  const _RetryPanel({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: BrandColors.gold, foregroundColor: BrandColors.navy),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

/// Slow-drifting, blurred glows in the four game colors over the navy.
class _GlowBackdrop extends CustomPainter {
  _GlowBackdrop(this.time) : super(repaint: time);
  final Animation<double> time;

  // (color, x, y, phase, strength): warm colors stay faint so the navy stays clean.
  static const _orbs = [
    (BrandColors.red, 0.15, 0.2, 0.0, 0.10),
    (BrandColors.blue, 0.85, 0.25, 0.25, 0.18),
    (BrandColors.green, 0.2, 0.85, 0.5, 0.09),
    (BrandColors.blue, 0.82, 0.8, 0.75, 0.12),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.25),
          radius: 1.1,
          colors: [BrandColors.indigo, BrandColors.navy],
        ).createShader(rect),
    );
    final radius = size.shortestSide * 0.42;
    for (final (color, x, y, phase, strength) in _orbs) {
      final angle = (time.value + phase) * 2 * math.pi;
      final center = Offset(
        size.width * x + math.cos(angle) * radius * 0.18,
        size.height * y + math.sin(angle) * radius * 0.14,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: strength)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlowBackdrop oldDelegate) => false;
}
