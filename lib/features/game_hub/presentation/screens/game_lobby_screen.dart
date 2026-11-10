import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/features/dama/presentation/screens/dama_match_screen.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_paint.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/karta/presentation/screens/karta_match_screen.dart';
import 'package:friends_game_app/features/karta/presentation/widgets/karta_cards.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';
import 'package:friends_game_app/features/match/application/practice_launcher.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// Per-game copy for the lobby.
class _LobbyCopy {
  const _LobbyCopy(this.heroTitle, this.heroText, this.fairness);
  final String heroTitle;
  final String heroText;
  final String fairness;
}

const _copy = {
  GameCodes.ludo: _LobbyCopy(
    'Classic 1v1 Ludo',
    'Four tokens. Exact finish. Safe squares, captures and blockades.',
    'Dice, legal moves, turn timing and results are decided by the backend — not by this phone.',
  ),
  GameCodes.karta: _LobbyCopy(
    'ካርታ ላጥ ላጥ · Karta Lat Lat',
    'The chooser names a rank; the starter deals, for away, for me. Whoever gets it wins the round. First to 3.',
    'The deck is sealed before every call and revealed after the round, so anyone can check it was fair.',
  ),
  GameCodes.dama: _LobbyCopy(
    'Ethiopian Dama',
    'Flying kings. Capture is compulsory and the biggest capture must be taken.',
    'Legal moves, captures, the clock and results are decided by the backend — not by this phone.',
  ),
};

/// Rooms, practice and "join with code" for one game.
class GameLobbyScreen extends ConsumerWidget {
  const GameLobbyScreen({super.key, required this.gameCode});
  final String gameCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hub = ref.watch(gameHubControllerProvider);
    final wallet = ref.watch(walletControllerProvider).wallet;
    final modes = hub.modesFor(gameCode);
    final copy = _copy[gameCode] ?? _copy[GameCodes.ludo]!;

    return Scaffold(
      appBar: AppBar(title: Text(GameRoutes.displayName(gameCode)), actions: [
        TextButton.icon(
          onPressed: () => _joinWithCode(context, gameCode),
          icon: const Icon(Icons.vpn_key_outlined),
          label: const Text('Join with code'),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.read(gameHubControllerProvider.notifier).load(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          children: [
            _GameHero(gameCode: gameCode, title: copy.heroTitle, text: copy.heroText),
            const SizedBox(height: 16),
            if (practiceGameCodes.contains(gameCode))
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
                  title: const Text('Practice vs computer', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Free • Easy, Normal or Hard'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showPracticeSheet(context, ref, gameCode: gameCode),
                ),
              ),
            if (gameCode != GameCodes.ludo) ...[
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
                  title: const Text('How to play', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(gameCode == GameCodes.karta ? 'Call, lat lat, catch it' : 'Compulsory capture, flying kings'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => gameCode == GameCodes.karta ? showKartaRules(context) : showDamaRules(context),
                ),
              ),
            ],
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
              'Open a live lobby, mark ready, then connect with another ready player.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (hub.loading && modes.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (hub.error != null && modes.isEmpty)
              _LobbyError(
                message: hub.error!,
                onRetry: () => ref.read(gameHubControllerProvider.notifier).load(),
              )
            else if (modes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No rooms are open right now.')),
              )
            else
              ...modes.map((mode) {
                final canAfford = wallet != null && wallet.availableBalance >= BigInt.from(mode.stakeAmountMinor);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ModeCard(
                    mode: mode,
                    canAfford: canAfford,
                    onPlay: canAfford ? () => context.push(GameRoutes.matchmaking(gameCode), extra: mode) : () => context.push('/deposit'),
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
                          Text(copy.fairness, style: Theme.of(context).textTheme.bodySmall),
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

Future<void> _joinWithCode(BuildContext context, String gameCode) async {
  final joined = await showDialog<({String matchId, String? gameCode})>(context: context, builder: (_) => const _JoinCodeDialog());
  // The code decides the game (a friend may have sent a code for another game).
  if (joined != null && context.mounted) context.go(GameRoutes.match(joined.gameCode ?? gameCode, joined.matchId));
}

/// Enter a friend's invite code; joining creates the match immediately.
class _JoinCodeDialog extends ConsumerStatefulWidget {
  const _JoinCodeDialog();
  @override
  ConsumerState<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends ConsumerState<_JoinCodeDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _code.text.trim().length < 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final joined = await ref.read(liveLobbyControllerProvider.notifier).joinInvite(_code.text);
      if (mounted) Navigator.pop(context, joined);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is InviteJoinException ? error.message : 'Could not join. Check your connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Join with code'),
        content: TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: 'ABCDE-FGHJK', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Join'),
          ),
        ],
      );
}

class _GameHero extends StatelessWidget {
  const _GameHero({required this.gameCode, required this.title, required this.text});
  final String gameCode;
  final String title;
  final String text;

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
            clipBehavior: Clip.antiAlias,
            child: gameHeroArt(gameCode),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(text, style: Theme.of(context).textTheme.bodyMedium),
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

/// Square art for a game's hero card.
Widget gameHeroArt(String gameCode) => switch (gameCode) {
      GameCodes.dama => const DamaBoardArt(),
      GameCodes.karta => const KartaArt(),
      _ => const Icon(Icons.grid_view_rounded, size: 34),
    };
