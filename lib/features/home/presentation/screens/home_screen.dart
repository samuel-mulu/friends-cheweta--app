import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      onRefresh: () async {
        await Future.wait([
          ref.read(gameHubControllerProvider.notifier).load(),
          ref.read(walletControllerProvider.notifier).refresh(),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [
          SectionHeader(title: 'Play now'),
          LiveGamesGrid(),
          SizedBox(height: 16),
          _JoinCodeCard(),
          SizedBox(height: 24),
          SectionHeader(title: 'Coming soon'),
          UpcomingGamesRow(),
        ],
      ),
    );
  }
}

class _JoinCodeCard extends ConsumerWidget {
  const _JoinCodeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showJoinWithCode(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.key_rounded, size: 20, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Got a code from a friend?', style: theme.textTheme.titleSmall),
                Text('Enter it to start your match.', style: theme.textTheme.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}
