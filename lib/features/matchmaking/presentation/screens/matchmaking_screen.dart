import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/matchmaking/domain/matchmaking_phase.dart';
import 'package:friends_game_app/features/matchmaking/domain/ready_player.dart';
import 'package:friends_game_app/features/matchmaking/presentation/controllers/matchmaking_controller.dart';
import 'package:friends_game_app/features/matchmaking/presentation/widgets/match_found_overlay.dart';

class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> {
  bool _started = false;
  bool _navigatingToMatch = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    Future.microtask(() => ref.read(matchmakingControllerProvider.notifier).openLobby(widget.mode.id));
  }

  void _enterMatch(String matchId) {
    if (_navigatingToMatch) return;
    _navigatingToMatch = true;
    ref.read(matchmakingControllerProvider.notifier).markEnteringMatch();
    ref.read(matchmakingControllerProvider.notifier).resetLocal();
    context.go('/ludo/match/$matchId');
  }

  String _statusMessage(MatchmakingState state) {
    return switch (state.phase) {
      MatchmakingPhase.browsing => 'Tap ready to join the live lobby for this room.',
      MatchmakingPhase.waitingInLobby => 'You are in the live lobby. Waiting for one more ready player.',
      MatchmakingPhase.pairing => 'Two players are ready. Starting the match…',
      MatchmakingPhase.matchFound => 'Opponent found. Get ready…',
      MatchmakingPhase.enteringMatch => 'Entering the table…',
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchmakingControllerProvider);
    final controller = ref.read(matchmakingControllerProvider.notifier);
    final socket = ref.watch(gameSocketStatusProvider);
    final players = state.readyPlayers;
    final match = state.match;

    return PopScope(
      canPop: !state.isReady,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && state.isReady) _confirmCancel(context);
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: Text(state.isMatched ? 'Match found' : widget.mode.name),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: state.isReady ? () => _confirmCancel(context) : () => context.pop(),
              ),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.screen),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_statusMessage(state), style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Stake ${MoneyFormatter.minorToEtb(BigInt.from(widget.mode.stakeAmountMinor))} locks when you go ready. When 2 players are ready, the match starts automatically.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _ConnectionChip(status: socket),
                        const SizedBox(width: 8),
                        Chip(
                          avatar: const Icon(Icons.people_alt_outlined, size: 16),
                          label: Text('${state.readyCount} ready'),
                        ),
                        if (state.phase == MatchmakingPhase.pairing) ...[
                          const SizedBox(width: 8),
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ],
                      ],
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 16),
                    Text('Live lobby', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Expanded(
                      child: players.isEmpty
                          ? _EmptyReadyList(isReady: state.isReady)
                          : ListView.separated(
                              itemCount: players.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) => _ReadyPlayerTile(player: players[index]),
                            ),
                    ),
                    if (!state.isMatched && state.isReady)
                      OutlinedButton(
                        onPressed: state.busy ? null : () => _confirmCancel(context),
                        child: Text(state.busy ? 'Updating…' : 'Leave lobby'),
                      )
                    else if (!state.isMatched)
                      FilledButton(
                        onPressed: state.busy ? null : () => controller.goReady(widget.mode.id),
                        child: Text(state.busy ? 'Locking stake…' : 'I am ready to play'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (state.showMatchFound && match != null)
            MatchFoundOverlay(
              selfName: controller.selfDisplayName(),
              opponentName: controller.opponentDisplayName(),
              stakeAmountMinor: match.stakeAmountMinor > 0 ? match.stakeAmountMinor : widget.mode.stakeAmountMinor,
              onComplete: () => _enterMatch(match.id),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave lobby?'),
        content: const Text('Your locked stake will be returned to your available balance.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay ready')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave lobby')),
        ],
      ),
    );
    if (shouldCancel != true || !context.mounted) return;
    await ref.read(matchmakingControllerProvider.notifier).cancel();
    if (!context.mounted) return;
    if (!ref.read(matchmakingControllerProvider).isReady) context.pop();
  }
}

class _EmptyReadyList extends StatelessWidget {
  const _EmptyReadyList({required this.isReady});

  final bool isReady;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isReady ? Icons.hourglass_top_rounded : Icons.people_outline_rounded,
            size: 40,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            isReady ? 'You are the first ready player.' : 'Nobody is ready yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 6),
          Text(
            isReady
                ? 'Other players will see your name here in real time.'
                : 'Go ready and your name will appear in this shared lobby.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReadyPlayerTile extends StatelessWidget {
  const _ReadyPlayerTile({required this.player});

  final ReadyPlayer player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: player.isSelf ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          child: Text(
            player.displayName.isNotEmpty ? player.displayName[0].toUpperCase() : '?',
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
        ),
        title: Text(player.isSelf ? '${player.displayName} (You)' : player.displayName),
        subtitle: Text('Ready • ${MoneyFormatter.minorToEtb(BigInt.from(player.stakeAmountMinor))} locked'),
        trailing: Chip(
          label: Text(player.isSelf ? 'You' : 'Waiting'),
          avatar: Icon(
            player.isSelf ? Icons.check_circle_outline : Icons.circle_outlined,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.status});
  final GameSocketStatus status;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      GameSocketStatus.connected => 'Live',
      GameSocketStatus.connecting => 'Connecting…',
      GameSocketStatus.recovering => 'Reconnecting…',
      GameSocketStatus.disconnected => 'Offline',
    };
    final icon = status == GameSocketStatus.connected ? Icons.wifi_rounded : Icons.wifi_off_rounded;
    return Chip(avatar: Icon(icon, size: 16), label: Text(text));
  }
}
