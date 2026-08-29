import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/history/presentation/controllers/match_history_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

class LudoResultScreen extends ConsumerStatefulWidget {
  const LudoResultScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<LudoResultScreen> createState() => _LudoResultScreenState();
}

class _LudoResultScreenState extends ConsumerState<LudoResultScreen> {
  Timer? _poller;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(const Duration(seconds: 2), (_) {
      final current = ref.read(matchDetailProvider(widget.matchId)).asData?.value;
      if (current == null || current.status == 'FINISHING') {
        if (_polls < 15) {
          setState(() => _polls++);
          ref.invalidate(matchDetailProvider(widget.matchId));
        }
      } else {
        _poller?.cancel();
        if (current.status == 'FINISHED') {
          ref.invalidate(walletControllerProvider);
          ref.invalidate(matchHistoryControllerProvider);
        }
      }
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(matchDetailProvider(widget.matchId));
    final me = ref.watch(authControllerProvider).user?.id;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Match result')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) {
          if (_polls < 15) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading settlement details…'),
                ],
              ),
            );
          }
          return AppErrorView(
            message: 'The result is confirmed, but settlement details could not be loaded yet.',
            onRetry: () => ref.invalidate(matchDetailProvider(widget.matchId)),
          );
        },
        data: (match) {
          final mine = me == null ? null : match.participant(me);
          final won = mine?.resultPosition == 1 || (match.winnerOrder.isNotEmpty && match.winnerOrder.first == me);
          final settlement = match.settlement;
          final processing = match.status == 'FINISHING' || settlement == null;
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 20),
                CircleAvatar(radius: 38, child: Icon(won ? Icons.emoji_events_rounded : Icons.sports_esports_rounded, size: 38)),
                const SizedBox(height: 18),
                Text(won ? 'Victory' : 'Match complete', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(won ? 'Your result is confirmed by the server.' : 'The server has confirmed the final result.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(children: [
                      _ResultRow(label: 'Stake', value: MoneyFormatter.minorToEtb(BigInt.from(match.stakeAmountMinor))),
                      if (settlement != null) ...[
                        _ResultRow(label: 'Pot', value: MoneyFormatter.minorToEtb(BigInt.from(settlement.potAmountMinor))),
                        _ResultRow(label: 'Platform fee', value: MoneyFormatter.minorToEtb(BigInt.from(settlement.platformFeeMinor))),
                        _ResultRow(label: 'Winner payout', value: MoneyFormatter.minorToEtb(BigInt.from(settlement.payoutAmountMinor))),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                if (processing)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Result confirmed. Prize settlement is processing…', style: Theme.of(context).textTheme.bodyMedium)),
                      ]),
                    ),
                  )
                else
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.verified_rounded),
                      title: const Text('Settlement complete'),
                      subtitle: const Text('Wallet and ledger were updated by the backend.'),
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: () => context.go('/ludo'), icon: const Icon(Icons.replay_rounded), label: const Text('Play again')),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: () => context.go('/home'), child: const Text('Back to home')),
                const SizedBox(height: 10),
                TextButton(onPressed: () => context.push('/history/${widget.matchId}'), child: const Text('View match details')),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [Expanded(child: Text(label)), Text(value, style: Theme.of(context).textTheme.labelLarge)]),
      );
}
