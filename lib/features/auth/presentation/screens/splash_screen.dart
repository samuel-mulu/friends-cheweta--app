import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/app/router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';
import 'package:friends_game_app/core/widgets/token_hop_loader.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';

/// Brand intro while the session is restored.
///
/// It continues the phone's own launch screen: the mark starts in the exact
/// centre on the same night colour, draws itself, then rises while
/// FRIENDS ጨዋታ arrives below. The router leaves when the intro is done and the
/// session is known (usually instant). If start-up takes longer, a gold token
/// hops along a row of squares with an honest status line, and Retry appears
/// when the server cannot be reached — never an endless spinner alone.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
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
    super.dispose();
  }

  double _part(double start, double end, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_intro.value - start) / (end - start)).clamp(0.0, 1.0).toDouble());

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final failed = auth.error != null && !auth.loading;

    return Scaffold(
      backgroundColor: AppColors.night,
      body: AnimatedBuilder(
        animation: _intro,
        builder: (context, _) {
          // 0–0.55: the mark draws itself in the centre (where the phone left it).
          // 0.5–0.9: it rises; the name and line arrive below.
          final rise = _part(0.5, 0.9);
          final word = _part(0.6, 0.95);
          final tagline = _part(0.75, 1);
          // Full width and height: everything is laid out from the centre.
          return Stack(fit: StackFit.expand, children: [
            Align(
              alignment: Alignment(0, -0.24 * rise),
              child: AppLogoMark(size: 104, reveal: _part(0, 0.55, Curves.linear)),
            ),
            Align(
              alignment: const Alignment(0, 0.16),
              child: Opacity(
                opacity: word,
                child: Transform.translate(
                  offset: Offset(0, 16 * (1 - word)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        'FRIENDS',
                        // Letters close in as they arrive.
                        style: AppType.display(size: 40, color: AppColors.ink, height: 44).copyWith(letterSpacing: 1.5 + 8 * (1 - word)),
                      ),
                      const SizedBox(width: 10),
                      Text('ጨዋታ', style: AppType.amharic(size: 32, color: AppColors.gold).copyWith(height: 1)),
                    ]),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: tagline,
                      child: Text(
                        'Ludo, Dama and Karta with friends',
                        textAlign: TextAlign.center,
                        style: AppType.ui(size: 14.5, weight: FontWeight.w500, color: AppColors.muted),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 140,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
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
                            ? _Waiting(key: const ValueKey('wait'), seconds: _waited)
                            : const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// A gold token hopping along a row of board squares, plus what is happening
/// when it takes long.
class _Waiting extends StatelessWidget {
  const _Waiting({super.key, required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    // Shown only when start-up is slower than the intro.
    final status = seconds < 2
        ? ''
        : seconds < 6
            ? 'Connecting…'
            : 'Waking up the server, almost there…';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const TokenHopLoader(),
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Text(
          status,
          key: ValueKey(status),
          style: AppType.ui(size: 13.5, weight: FontWeight.w500, color: AppColors.muted),
        ),
      ),
    ]);
  }
}

class _RetryPanel extends StatelessWidget {
  const _RetryPanel({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppType.ui(size: 14.5, color: AppColors.inkSoft, height: 20),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.onGold),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ]);
}
