import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
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
  GameCatalogEntry(code: 'LUDO', name: 'Ludo', tagline: 'Classic 1v1 · Race home', tile: AppColors.navy, route: '/ludo'),
  GameCatalogEntry(code: 'DAMA', name: 'Dama', tagline: 'Ethiopian draughts', tile: Color(0xFF5A3417), route: '/dama'),
  GameCatalogEntry(code: 'KARTA', name: 'Karta Lat Lat', tagline: 'Call the card, catch it first', tile: Color(0xFF0E4A33), route: '/karta'),
  GameCatalogEntry(code: 'BINGO', name: 'Bingo', tagline: 'Coming soon', tile: Color(0xFF2B2F45), icon: Icons.grid_on_rounded),
  GameCatalogEntry(code: 'CHESS', name: 'Chess', tagline: 'Coming soon', tile: Color(0xFF2B2F45), icon: Icons.castle_rounded),
  GameCatalogEntry(code: 'CARDS', name: 'Card Games', tagline: 'Coming soon', tile: Color(0xFF2B2F45), icon: Icons.style_rounded),
  GameCatalogEntry(code: 'TIC_TAC_TOE', name: 'Tic-Tac-Toe', tagline: 'Coming soon', tile: Color(0xFF2B2F45), icon: Icons.tag_rounded),
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

/// Fill the last row when the narrow grid has one card left.
class LiveGamesGrid extends StatelessWidget {
  const LiveGamesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final games = liveGames;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 3 : 2;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (index, game) in games.indexed)
            if (columns == 2 && games.length.isOdd && index == games.length - 1)
              SizedBox(width: constraints.maxWidth, child: LiveGameCard(entry: game, wide: true))
            else
              SizedBox(width: width, child: LiveGameCard(entry: game)),
        ],
      );
    });
  }
}

class LiveGameCard extends StatelessWidget {
  const LiveGameCard({super.key, required this.entry, this.wide = false});
  final GameCatalogEntry entry;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artwork = AspectRatio(
      aspectRatio: 1.25,
      child: Stack(fit: StackFit.expand, children: [
        GameArt(code: entry.code, padding: 14),
        const Positioned(top: 10, left: 10, child: _LiveBadge()),
      ]),
    );
    final details = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(entry.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
      ]),
    );
    return Semantics(
      button: true,
      label: 'Play ${entry.name}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(entry.route!),
          child: wide
              ? LayoutBuilder(builder: (context, constraints) {
                  final artWidth = constraints.maxWidth * 0.42;
                  return Stack(children: [
                    Padding(
                      padding: EdgeInsets.only(left: artWidth),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: artWidth / 1.25),
                        child: Row(children: [
                          Expanded(child: details),
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ]),
                      ),
                    ),
                    Positioned(left: 0, top: 0, bottom: 0, width: artWidth, child: artwork),
                  ]);
                })
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [artwork, details]),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(999)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          LiveDot(color: Color(0xFF4ADE80), size: 6),
          SizedBox(width: 5),
          Text('Live', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Upcoming games: small and quiet, in one scrolling row.
class UpcomingGamesRow extends StatelessWidget {
  const UpcomingGamesRow({super.key});

  @override
  Widget build(BuildContext context) {
    final games = upcomingGames;
    return SizedBox(
      height: 112,
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
          width: 78,
          child: Column(children: [
            Opacity(
              opacity: 0.7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox.square(dimension: 72, child: GameArt(code: entry.code)),
              ),
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
