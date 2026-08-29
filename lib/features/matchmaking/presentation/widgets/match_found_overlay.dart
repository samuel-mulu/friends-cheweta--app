import 'dart:async';
import 'package:flutter/material.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';

class MatchFoundOverlay extends StatefulWidget {
  const MatchFoundOverlay({
    super.key,
    required this.selfName,
    required this.opponentName,
    required this.stakeAmountMinor,
    required this.onComplete,
    this.countdownSeconds = 3,
  });

  final String selfName;
  final String opponentName;
  final int stakeAmountMinor;
  final VoidCallback onComplete;
  final int countdownSeconds;

  @override
  State<MatchFoundOverlay> createState() => _MatchFoundOverlayState();
}

class _MatchFoundOverlayState extends State<MatchFoundOverlay> with TickerProviderStateMixin {
  late final AnimationController _slideController;
  late final AnimationController _pulseController;
  late final Animation<double> _leftSlide;
  late final Animation<double> _rightSlide;
  late final Animation<double> _vsScale;
  Timer? _countdownTimer;
  int _secondsLeft = 0;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.countdownSeconds;

    _slideController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

    _leftSlide = Tween<double>(begin: -1.2, end: 0).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack));
    _rightSlide = Tween<double>(begin: 1.2, end: 0).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack));
    _vsScale = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _slideController, curve: Curves.elasticOut));

    _slideController.forward();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        _finish();
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Text(
                'Match found',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                'Stakes secured • ${MoneyFormatter.minorToEtb(BigInt.from(widget.stakeAmountMinor))}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.outline),
              ),
              const SizedBox(height: 48),
              SizedBox(
                height: 120,
                child: AnimatedBuilder(
                  animation: _slideController,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Align(
                          alignment: Alignment(-0.55 + (_leftSlide.value * 0.55), 0),
                          child: _PlayerAvatar(name: widget.selfName, label: 'You', scheme: scheme),
                        ),
                        Transform.scale(
                          scale: _vsScale.value,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: Text('VS', style: Theme.of(context).textTheme.labelLarge),
                          ),
                        ),
                        Align(
                          alignment: Alignment(0.55 + (_rightSlide.value * 0.55), 0),
                          child: _PlayerAvatar(name: widget.opponentName, label: 'Opponent', scheme: scheme),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),
              ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.08).animate(_pulseController),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.primary, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$_secondsLeft',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: scheme.primary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Entering the table…',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.name, required this.label, required this.scheme});

  final String name;
  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 42,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(fontSize: 28, color: scheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.outline)),
        Text(
          name,
          style: Theme.of(context).textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
