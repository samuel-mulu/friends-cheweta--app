import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/history/domain/match_history.dart';
import 'package:friends_game_app/features/history/presentation/controllers/match_history_controller.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchHistoryControllerProvider);
    final me = ref.watch(authControllerProvider).user?.id;
    return RefreshIndicator(
      onRefresh: () => ref.read(matchHistoryControllerProvider.notifier).load(),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 24, AppSpacing.screen, 12),
            sliver: SliverToBoxAdapter(child: Text('Match history', style: Theme.of(context).textTheme.headlineSmall)),
          ),
          if (state.loading && state.items.isEmpty)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (state.error != null && state.items.isEmpty)
            SliverFillRemaining(child: AppErrorView(message: state.error!, onRetry: () => ref.read(matchHistoryControllerProvider.notifier).load()))
          else if (state.items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('Your completed and active matches will appear here.')))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 28),
              sliver: SliverList.separated(
                itemCount: state.items.length + (state.nextCursor != null ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  if (index == state.items.length) {
                    return Center(
                      child: TextButton(
                        onPressed: state.loadingMore ? null : () => ref.read(matchHistoryControllerProvider.notifier).loadMore(),
                        child: state.loadingMore ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
                      ),
                    );
                  }
                  return _MatchCard(match: state.items[index], myUserId: me);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.myUserId});
  final MatchHistoryItem match;
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final mine = myUserId == null ? null : match.participant(myUserId!);
    final won = mine?.resultPosition == 1 || (match.winnerOrder.isNotEmpty && match.winnerOrder.first == myUserId);
    MatchParticipantSummary? opponent;
    for (final participant in match.participants) {
      if (participant.userId != myUserId) {
        opponent = participant;
        break;
      }
    }
    final settled = match.settlement != null;
    final subtitle = match.status == 'FINISHED' ? (won ? 'Won${settled ? ' · Settled' : ''}' : 'Finished') : _prettyStatus(match.status);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/history/${match.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(child: Icon(won ? Icons.emoji_events_rounded : Icons.sports_esports_rounded)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(match.modeName.isEmpty ? match.gameName : match.modeName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(opponent == null ? subtitle : '$subtitle · vs ${opponent.fullName}', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 5),
                Text(DateFormat('MMM d, y · h:mm a').format(match.createdAt.toLocal()), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(MoneyFormatter.minorToEtb(BigInt.from(match.stakeAmountMinor)), style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ]),
        ),
      ),
    );
  }

  String _prettyStatus(String value) => value.toLowerCase().replaceAll('_', ' ').split(' ').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}

