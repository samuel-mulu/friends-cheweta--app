import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/game_hub/presentation/screens/game_lobby_screen.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/game_grid.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// The hub: games you can play now first, then a friend's code, then what is coming.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () async {
        await Future.wait([
          ref.read(gameHubControllerProvider.notifier).load(),
          ref.read(walletControllerProvider.notifier).refresh(),
        ]);
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: const [
              SectionHeader(title: 'Play now'),
              LiveGamesGrid(),
              SizedBox(height: 12),
              _JoinCodeCard(),
              SizedBox(height: 28),
              SectionHeader(title: 'Coming soon'),
              UpcomingGamesRow(),
            ],
          ),
        ),
      ),
    );
  }
}

class _JoinCodeCard extends ConsumerWidget {
  const _JoinCodeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return AppPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      color: palette.background,
      onTap: () => showJoinWithCode(context, ref),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: palette.surfaceAlt, borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.key_rounded, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Got a code from a friend?', style: theme.textTheme.titleSmall),
            Text('Enter it to start your match.', style: theme.textTheme.bodySmall),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
      ]),
    );
  }
}
