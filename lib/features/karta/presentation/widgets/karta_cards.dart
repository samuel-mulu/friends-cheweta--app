import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';
import 'package:friends_game_app/features/karta/domain/karta_models.dart';

/// Karta's look: a green felt table with gold accents, classic white card
/// faces, and a Friends card back (navy, gold lattice, the F monogram).
abstract final class KartaPalette {
  static const feltTop = Color(0xFF14704A);
  static const feltBottom = Color(0xFF07331F);
  static const gold = Color(0xFFFFC83D);
  static const goldDeep = Color(0xFFC98A00);
  static const ink = Color(0xFF1B1B1F);
  static const red = Color(0xFFD32F2F);
}

/// Card size from a width (classic 5:7 proportions).
Size kartaCardSize(double width) => Size(width, width * 1.4);

class KartaCardFace extends StatelessWidget {
  const KartaCardFace({super.key, required this.card, this.width = 64, this.highlight = false});
  final KartaCard card;
  final double width;

  /// Gold glow for the card that won the round.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final size = kartaCardSize(width);
    final color = card.suit.red ? KartaPalette.red : KartaPalette.ink;
    final corner = TextStyle(color: color, fontSize: width * 0.2, fontWeight: FontWeight.w800, height: 1);
    final face = ['J', 'Q', 'K'].contains(card.rank);
    return Semantics(
      label: '${card.rank} of ${card.suit.name}',
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(width * 0.1),
          border: Border.all(color: highlight ? KartaPalette.gold : const Color(0xFFDADDE2), width: highlight ? 2.5 : 1),
          boxShadow: [
            if (highlight) BoxShadow(color: KartaPalette.gold.withValues(alpha: 0.7), blurRadius: 18, spreadRadius: 2),
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3)),
          ],
        ),
        child: Stack(children: [
          Positioned(
            left: width * 0.08,
            top: width * 0.07,
            child: Column(children: [Text(card.rank, style: corner), Text(card.suit.symbol, style: corner)]),
          ),
          Positioned(
            right: width * 0.08,
            bottom: width * 0.07,
            child: Transform.rotate(
              angle: math.pi,
              child: Column(children: [Text(card.rank, style: corner), Text(card.suit.symbol, style: corner)]),
            ),
          ),
          Center(
            child: face
                ? Container(
                    width: width * 0.5,
                    height: width * 0.66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(width * 0.06),
                      color: color.withValues(alpha: 0.06),
                    ),
                    child: Text(card.rank, style: TextStyle(color: color, fontSize: width * 0.34, fontWeight: FontWeight.w900)),
                  )
                : Text(card.suit.symbol, style: TextStyle(color: color, fontSize: width * 0.46, height: 1)),
          ),
        ]),
      ),
    );
  }
}

class KartaCardBack extends StatelessWidget {
  const KartaCardBack({super.key, this.width = 64});
  final double width;

  @override
  Widget build(BuildContext context) {
    final size = kartaCardSize(width);
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        border: Border.all(color: Colors.white, width: width * 0.05),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.06),
        child: CustomPaint(painter: _BackPainter()),
      ),
    );
  }
}

class _BackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrandColors.indigo, BrandColors.navy],
        ).createShader(rect),
    );
    // Gold lattice.
    final line = Paint()
      ..color = KartaPalette.gold.withValues(alpha: 0.22)
      ..strokeWidth = size.width * 0.02;
    final step = size.width / 5;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    // The F monogram in the middle.
    final mark = size.width * 0.62;
    canvas.save();
    canvas.translate((size.width - mark) / 2, (size.height - mark) / 2);
    const AppLogoPainter(tile: false).paint(canvas, Size.square(mark));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BackPainter oldDelegate) => false;
}

/// A card that arrives face down and flips face up (plays once on insert).
class KartaFlipIn extends StatelessWidget {
  const KartaFlipIn(
      {super.key, required this.card, this.width = 64, this.highlight = false, this.duration = const Duration(milliseconds: 420)});
  final KartaCard card;
  final double width;
  final bool highlight;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          final angle = (1 - t) * math.pi;
          final showFace = angle < math.pi / 2;
          return Transform.translate(
            offset: Offset(0, -24 * (1 - t)),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY(showFace ? angle : angle - math.pi),
              child: showFace ? KartaCardFace(card: card, width: width, highlight: highlight) : KartaCardBack(width: width),
            ),
          );
        },
      );
}

/// Hub/lobby art: three fanned cards on felt.
class KartaArt extends StatelessWidget {
  const KartaArt({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final w = constraints.biggest.shortestSide * 0.42;
        Widget card(Widget child, double angle, double dx) => Transform.translate(
              offset: Offset(dx * w, w * 0.08),
              child: Transform.rotate(angle: angle, alignment: Alignment.bottomCenter, child: child),
            );
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(colors: [KartaPalette.feltTop, KartaPalette.feltBottom], radius: 0.9),
          ),
          child: Center(
            child: Stack(alignment: Alignment.center, children: [
              card(KartaCardBack(width: w), -0.32, -0.42),
              card(KartaCardFace(card: const KartaCard('K', KartaSuit.hearts), width: w), 0.3, 0.42),
              card(KartaCardFace(card: const KartaCard('5', KartaSuit.spades), width: w, highlight: true), 0, 0),
            ]),
          ),
        );
      });
}
