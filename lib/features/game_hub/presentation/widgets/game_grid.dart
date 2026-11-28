import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_paint.dart';
import 'package:friends_game_app/features/karta/presentation/widgets/karta_cards.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_painter.dart';

/// One entry in the games catalog. Live games open; the rest are announced.
class GameCatalogEntry {
  const GameCatalogEntry({
    required this.code,
    required this.name,
    required this.tagline,
    required this.tile,
    this.icon,
    this.route,
  });

  final String code;
  final String name;
  final String tagline;

  /// Background of the game's art tile (one flat colour per game).
  final Color tile;
  final IconData? icon;

  /// Null means "coming soon".
  final String? route;

  bool get live => route != null;
}

/// Live games first (in the order players use them), then what is coming.
const gameCatalog = <GameCatalogEntry>[
  GameCatalogEntry(code: 'LUDO', name: 'Ludo', tagline: 'Race home · 1v1 to 4 players', tile: Color(0xFF16264F), route: '/ludo'),
  GameCatalogEntry(code: 'DAMA', name: 'Dama', tagline: 'Ethiopian draughts', tile: Color(0xFF4A2C14), route: '/dama'),
  GameCatalogEntry(code: 'KARTA', name: 'Karta Lat Lat', tagline: 'Call the card, catch it first', tile: Color(0xFF0E3B2A), route: '/karta'),
  GameCatalogEntry(code: 'BINGO', name: 'Bingo', tagline: 'Coming soon', tile: AppColors.raised, icon: Icons.grid_on_rounded),
  GameCatalogEntry(code: 'CHESS', name: 'Chess', tagline: 'Coming soon', tile: AppColors.raised, icon: Icons.castle_rounded),
  GameCatalogEntry(code: 'CARDS', name: 'Card Games', tagline: 'Coming soon', tile: AppColors.raised, icon: Icons.style_rounded),
  GameCatalogEntry(code: 'TIC_TAC_TOE', name: 'Tic-Tac-Toe', tagline: 'Coming soon', tile: AppColors.raised, icon: Icons.tag_rounded),
];

List<GameCatalogEntry> get liveGames => gameCatalog.where((e) => e.live).toList();
List<GameCatalogEntry> get upcomingGames => gameCatalog.where((e) => !e.live).toList();

/// A game's art on its tile colour.
class GameArt extends StatelessWidget {
  const GameArt({super.key, required this.code, this.padding = 10});
  final String code;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final entry = gameCatalog.firstWhere((e) => e.code == code, orElse: () => gameCatalog.first);
    return ColoredBox(
      color: entry.tile,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: switch (code) {
          // The board is square: keep it whole inside any tile shape.
          'LUDO' => Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(borderRadius: BorderRadius.circular(8), child: const CustomPaint(painter: LudoBoardPainter())),
              ),
            ),
          'KARTA' => const KartaArt(),
          'DAMA' => const DamaBoardArt(),
          _ => Icon(entry.icon, size: 30, color: Colors.white.withValues(alpha: 0.7)),
        },
      ),
    );
  }
}

/// The live games as full-width table cards (two or three across on wide screens).
class LiveGamesGrid extends StatelessWidget {
  const LiveGamesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final games = liveGames;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 960 ? 3 : (constraints.maxWidth >= 600 ? 2 : 1);
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final game in games) SizedBox(width: width, child: LiveGameCard(entry: game))],
      );
    });
  }
}

/// A live game: its art on the left, name and line, and a Live mark.
class LiveGameCard extends StatelessWidget {
  const LiveGameCard({super.key, required this.entry, this.wide = false});
  final GameCatalogEntry entry;

  /// Kept for older call sites; every card is a wide row now.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final art = 104.0 * textScale.clamp(1, 1.3);
    return Semantics(
      button: true,
      label: 'Play ${entry.name}',
      excludeSemantics: true,
      child: AppPanel(
        padding: EdgeInsets.zero,
        onTap: () => context.push(entry.route!),
        child: Row(children: [
          SizedBox.square(dimension: art, child: GameArt(code: entry.code, padding: 16)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.display(size: 25, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 3),
                Text(entry.tagline, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: 14)),
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  LiveDot(size: 7, color: palette.live),
                  const SizedBox(width: 6),
                  Text('Live', style: AppType.ui(size: 13, weight: FontWeight.w600, color: palette.live)),
                ]),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

/// Upcoming games: small and quiet, in one scrolling row.
class UpcomingGamesRow extends StatelessWidget {
  const UpcomingGamesRow({super.key});

  @override
  Widget build(BuildContext context) {
    final games = upcomingGames;
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: games.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _UpcomingTile(entry: games[i]),
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.entry});
  final GameCatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${entry.name}, coming soon',
      child: GestureDetector(
        onTap: () => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('${entry.name} is coming soon.'))),
        child: SizedBox(
          width: 76,
          child: Column(children: [
            Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppPalette.of(context).border),
              ),
              child: Icon(entry.icon, size: 26, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 6),
            Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall),
          ]),
        ),
      ),
    );
  }
}

/// Every game, live first (the "All games" screen).
class GameGrid extends StatelessWidget {
  const GameGrid({super.key});

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LiveGamesGrid(),
        SizedBox(height: 24),
        SectionHeader(title: 'Coming soon'),
        UpcomingGamesRow(),
      ]);
}
