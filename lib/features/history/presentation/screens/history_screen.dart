import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
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
      color: AppColors.gold,
      onRefresh: () => ref.read(matchHistoryControllerProvider.notifier).load(),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (state.loading && state.items.isEmpty)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (state.error != null && state.items.isEmpty)
            SliverFillRemaining(child: AppErrorView(message: state.error!, onRetry: () => ref.read(matchHistoryControllerProvider.notifier).load()))
          else if (state.items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: EmptyState(
                  icon: Icons.history_rounded,
                  title: 'No matches yet',
                  message: 'Your completed and active matches will appear here.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 28),
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
    final practice = match.isPractice;
    final subtitle = match.status == 'FINISHED'
        ? (won ? 'Won${settled && !practice ? ', settled' : ''}' : 'Finished')
        : _prettyStatus(match.status);
    // Practice is free: name it as such, never with the stake of the mode it borrowed.
    final title = practice ? '${match.gameName} practice' : (match.modeName.isEmpty ? match.gameName : match.modeName);

    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/history/${match.id}'),
      child: Row(children: [
        // Winning is gold; everything else stays quiet.
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: won ? palette.selected : palette.surfaceAlt, borderRadius: BorderRadius.circular(12)),
          child: Icon(
            won ? Icons.emoji_events_rounded : Icons.sports_esports_outlined,
            color: won ? AppColors.gold : theme.colorScheme.onSurfaceVariant,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(opponent == null ? subtitle : '$subtitle, vs ${opponent.fullName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Text(DateFormat('d MMM y, HH:mm').format(match.createdAt.toLocal()), style: theme.textTheme.bodySmall),
          ]),
        ),
        const SizedBox(width: 8),
        practice
            ? Text('Free', style: AppType.ui(size: 14, weight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant))
            : Text(MoneyFormatter.compactEtb(match.stakeAmountMinor), style: AppType.money(size: 17, color: palette.money)),
        Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
      ]),
    );
  }

  String _prettyStatus(String value) => value.toLowerCase().replaceAll('_', ' ').split(' ').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}

