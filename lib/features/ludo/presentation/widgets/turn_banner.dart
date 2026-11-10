import 'package:flutter/material.dart';
import 'package:friends_game_app/features/ludo/presentation/match_presenter.dart';
import 'package:friends_game_app/features/match/presentation/widgets/crown_icon.dart';

/// "YOUR TURN" / "SAMUEL'S TURN" pill in the current player's color. Pulses
/// when it is my move so it is impossible to miss.
class TurnBanner extends StatefulWidget {
  const TurnBanner({super.key, required this.banner});
  final TurnBannerData banner;

  @override
  State<TurnBanner> createState() => _TurnBannerState();
}

class _TurnBannerState extends State<TurnBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TurnBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banner.mine != widget.banner.mine) _sync();
  }

  void _sync() => widget.banner.mine ? _pulse.repeat(reverse: true) : (_pulse..stop()..value = 0);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = widget.banner;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: AnimatedBuilder(
        key: ValueKey(banner.text),
        animation: _pulse,
        builder: (context, child) => Transform.scale(scale: 1 + _pulse.value * 0.05, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: banner.color,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
            boxShadow: [BoxShadow(color: banner.color.withValues(alpha: 0.6), blurRadius: 14)],
          ),
          child: Text(
            banner.text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }
}

/// "👑 FIRST TO 2 HOME" under the banner when the match is not the classic 4.
class MatchGoalChip extends StatelessWidget {
  const MatchGoalChip({super.key, required this.tokensToWin});
  final int tokensToWin;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFFFC83D).withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const CrownIcon(size: 13),
          const SizedBox(width: 6),
          Text(
            'FIRST TO $tokensToWin HOME',
            style: const TextStyle(color: Color(0xFFFFE27A), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
          ),
        ]),
      );
}
