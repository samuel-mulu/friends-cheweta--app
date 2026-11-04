import 'package:flutter/material.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/game_grid.dart';

class GameHubScreen extends StatelessWidget {
  const GameHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          Text('Choose a game', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'One account, wallet and history across every game. More games are on the way.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          const GameGrid(),
        ],
      ),
    );
  }
}
