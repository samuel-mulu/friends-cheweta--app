import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_paint.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_painter.dart';

/// One entry in the games catalog. Ludo and Dama are live; the rest are announced.
class GameCatalogEntry {
  const GameCatalogEntry({
    required this.code,
    required this.name,
    required this.tagline,
    required this.colors,
    this.icon,
    this.route,
  });

  final String code;
  final String name;
  final String tagline;
  final List<Color> colors;
  final IconData? icon;

  /// Null means "coming soon".
  final String? route;

  bool get live => route != null;
}

const gameCatalog = <GameCatalogEntry>[
  GameCatalogEntry(
    code: 'LUDO',
    name: 'Ludo',
    tagline: 'Real-time • Play for stakes',
    colors: [Color(0xFF13306B), BrandColors.navy],
    route: '/ludo',
  ),
  GameCatalogEntry(
    code: 'BINGO',
    name: 'Bingo',
    tagline: 'Coming soon',
    colors: [Color(0xFF7B2FF7), Color(0xFF3A0CA3)],
    icon: Icons.grid_on_rounded,
  ),
  GameCatalogEntry(
    code: 'DAMA',
    name: 'Dama',
    tagline: 'Ethiopian • Flying kings',
    colors: [Color(0xFF8D5524), Color(0xFF3B1F0E)],
    route: '/dama',
  ),
  GameCatalogEntry(
    code: 'CARDS',
    name: 'Card Games',
    tagline: 'Coming soon',
    colors: [Color(0xFFD62828), Color(0xFF6A040F)],
    icon: Icons.style_rounded,
  ),
  GameCatalogEntry(
    code: 'TIC_TAC_TOE',
    name: 'Tic-Tac-Toe',
    tagline: 'Coming soon',
    colors: [Color(0xFF0FA3B1), Color(0xFF07575F)],
    icon: Icons.tag_rounded,
  ),
  GameCatalogEntry(
    code: 'CHESS',
    name: 'Chess',
    tagline: 'Coming soon',
    colors: [Color(0xFF495057), Color(0xFF212529)],
    icon: Icons.castle_rounded,
  ),
];

/// Grid of game tiles: live games open, upcoming ones show a "Coming soon" note.
class GameGrid extends StatelessWidget {
  const GameGrid({super.key, this.entries = gameCatalog});
  final List<GameCatalogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 520 ? 4 : 3;
        final tileWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final labelHeight = 46 * MediaQuery.textScalerOf(context).scale(1);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: spacing,
            // Square art + room for two label lines, at any text scale.
            mainAxisExtent: tileWidth + labelHeight,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) => GameTile(entry: entries[index]),
        );
      },
    );
  }
}

class GameTile extends StatelessWidget {
  const GameTile({super.key, required this.entry});
  final GameCatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void open() {
      if (entry.live) {
        context.push(entry.route!);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${entry.name} is coming soon. Stay tuned!')));
      }
    }

    return Semantics(
      button: true,
      label: entry.live ? 'Play ${entry.name}' : '${entry.name}, coming soon',
      child: GestureDetector(
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: entry.colors),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: entry.code == 'LUDO' || entry.code == 'DAMA'
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: entry.code == 'LUDO' ? const CustomPaint(painter: LudoBoardPainter()) : const DamaBoardArt(),
                            )
                          : Icon(entry.icon, size: 44, color: Colors.white.withValues(alpha: entry.live ? 1 : 0.85)),
                    ),
                  ),
                  if (!entry.live)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.black.withValues(alpha: 0.25),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _Badge(live: entry.live),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              entry.tagline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.live});
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: live ? const Color(0xFF1FA35A) : Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
        ),
        child: Text(
          live ? 'LIVE' : 'SOON',
          style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.8),
        ),
      );
}
