import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';

/// The app's loader: a gold token hops square to square along five cells, the
/// way a piece moves on a board. Respects "remove animations" (a still token).
class TokenHopLoader extends StatefulWidget {
  const TokenHopLoader({super.key, this.cell = 16});
  final double cell;

  @override
  State<TokenHopLoader> createState() => _TokenHopLoaderState();
}

class _TokenHopLoaderState extends State<TokenHopLoader> with SingleTickerProviderStateMixin {
  static const _cells = 5;
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _hop.stop();
    } else if (!_hop.isAnimating) {
      _hop.repeat();
    }
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    const gap = 6.0;
    final width = _cells * cell + (_cells - 1) * gap;
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: width,
        height: cell * 2.2,
        child: AnimatedBuilder(
          animation: _hop,
          builder: (context, _) {
            // Hop from cell i to i+1; back to the start after the last.
            final t = _hop.value * (_cells - 1);
            final i = t.floor().clamp(0, _cells - 2);
            final local = Curves.easeInOut.transform((t - i).clamp(0.0, 1.0).toDouble());
            final x = (i + local) * (cell + gap);
            final lift = math.sin(local * math.pi) * cell * 0.8;
            return Stack(clipBehavior: Clip.none, children: [
              for (var c = 0; c < _cells; c++)
                Positioned(
                  left: c * (cell + gap),
                  bottom: 0,
                  child: Container(
                    width: cell,
                    height: cell,
                    decoration: BoxDecoration(
                      color: c <= i ? AppColors.goldWash : AppColors.raised,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.line),
                    ),
                  ),
                ),
              Positioned(
                left: x + cell * 0.15,
                bottom: cell * 0.15 + lift,
                child: Container(
                  width: cell * 0.7,
                  height: cell * 0.7,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.night, width: 1.5),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}
