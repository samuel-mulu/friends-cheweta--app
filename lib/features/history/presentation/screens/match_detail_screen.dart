import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/history/presentation/controllers/match_history_controller.dart';

class MatchDetailScreen extends ConsumerWidget {
  const MatchDetailScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(matchDetailProvider(matchId));
    final me = ref.watch(authControllerProvider).user?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Match details')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppErrorView(message: 'Could not load this match.', onRetry: () => ref.invalidate(matchDetailProvider(matchId))),
        data: (match) {
          final mine = me == null ? null : match.participant(me);
          final won = mine?.resultPosition == 1 || (match.winnerOrder.isNotEmpty && match.winnerOrder.first == me);
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            children: [
              Text(won ? 'You won' : _status(match.status), style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              Text(match.modeName, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              _Row(label: 'Stake', value: MoneyFormatter.minorToEtb(BigInt.from(match.stakeAmountMinor))),
              _Row(label: 'Created', value: DateFormat('MMM d, y · h:mm a').format(match.createdAt.toLocal())),
              if (match.finishedAt != null) _Row(label: 'Finished', value: DateFormat('MMM d, y · h:mm a').format(match.finishedAt!.toLocal())),
              if (match.settlement != null) ...[
                const Divider(height: 32),
                Text('Settlement', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _Row(label: 'Pot', value: MoneyFormatter.minorToEtb(BigInt.from(match.settlement!.potAmountMinor))),
                _Row(label: 'Platform fee', value: MoneyFormatter.minorToEtb(BigInt.from(match.settlement!.platformFeeMinor))),
                _Row(label: 'Winner payout', value: MoneyFormatter.minorToEtb(BigInt.from(match.settlement!.payoutAmountMinor))),
              ],
              const Divider(height: 32),
              Text('Players', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...match.participants.map((p) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${p.seat + 1}')),
                    title: Text(p.userId == me ? '${p.fullName} (You)' : p.fullName),
                    trailing: p.resultPosition == null ? null : Text('#${p.resultPosition}'),
                  )),
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: () => context.push('/history/$matchId/replay'), icon: const Icon(Icons.receipt_long_outlined), label: const Text('View match timeline')),
            ],
          );
        },
      ),
    );
  }

  String _status(String value) => value.toLowerCase().replaceAll('_', ' ').split(' ').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)), Text(value, style: Theme.of(context).textTheme.labelLarge)]),
      );
}
