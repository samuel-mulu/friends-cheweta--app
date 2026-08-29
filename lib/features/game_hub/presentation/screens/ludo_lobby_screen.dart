import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

class LudoLobbyScreen extends ConsumerWidget {
  const LudoLobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(gameHubControllerProvider);
    final wallet = ref.watch(walletControllerProvider).wallet;

    return Scaffold(
      appBar: AppBar(title: const Text('Ludo')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(gameHubControllerProvider.notifier).load(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          children: [
            const _LudoHero(),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Choose a room', style: Theme.of(context).textTheme.titleLarge),
                ),
                if (wallet != null)
                  Text(
                    MoneyFormatter.minorToEtb(wallet.availableBalance),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Your stake is locked from your wallet as soon as you mark yourself ready.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (hub.loading && hub.ludoModes.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (hub.error != null && hub.ludoModes.isEmpty)
              _LobbyError(
                message: hub.error!,
                onRetry: () => ref.read(gameHubControllerProvider.notifier).load(),
              )
            else
              ...hub.ludoModes.map((mode) {
                final canAfford = wallet != null && wallet.availableBalance >= BigInt.from(mode.stakeAmountMinor);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModeCard(
                    mode: mode,
                    canAfford: canAfford,
                    onPlay: canAfford
                        ? () => context.push('/ludo/matchmaking', extra: mode)
                        : () => context.push('/deposit'),
                  ),
                );
              }),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Server-authoritative play', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            'Dice, legal moves, turn timing and results are decided by the backend — not by this phone.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LudoHero extends StatelessWidget {
  const _LudoHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.grid_view_rounded, size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Classic 1v1 Ludo', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Four tokens. Exact finish. Safe squares, captures and blockades.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.canAfford, required this.onPlay});

  final GameMode mode;
  final bool canAfford;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mode.name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 5),
                      Text(
                        '${mode.playerCount} players • ${mode.turnDurationSeconds}s turns',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  MoneyFormatter.minorToEtb(BigInt.from(mode.stakeAmountMinor)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Estimated winner payout ${MoneyFormatter.minorToEtb(BigInt.from(mode.estimatedWinnerPayoutMinor))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton(
                  onPressed: onPlay,
                  child: Text(canAfford ? 'Open room' : 'Add funds'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LobbyError extends StatelessWidget {
  const _LobbyError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 36),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
