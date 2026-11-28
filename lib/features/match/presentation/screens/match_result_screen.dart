import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/history/presentation/controllers/match_history_controller.dart';
import 'package:friends_game_app/features/match/application/practice_launcher.dart';
import 'package:friends_game_app/features/match/application/rematch_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// Result of any game: outcome, settlement, rematch or play again.
class MatchResultScreen extends ConsumerStatefulWidget {
  const MatchResultScreen({super.key, required this.gameCode, required this.matchId});
  final String gameCode;
  final String matchId;

  @override
  ConsumerState<MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends ConsumerState<MatchResultScreen> {
  Timer? _poller;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(rematchControllerProvider.notifier).attach(widget.matchId));
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
    ref.listen(rematchControllerProvider.select((s) => s.newMatchId), (previous, next) {
      if (next != null && next != previous) context.go(GameRoutes.match(widget.gameCode, next));
    });
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(GameRoutes.lobby(widget.gameCode));
      },
      child: Scaffold(
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
            final draw = match.isDraw;
            final won = !draw && (mine?.resultPosition == 1 || (match.winnerOrder.isNotEmpty && match.winnerOrder.first == me));
            // 3–4 players: say where I finished ("2nd of 4").
            final players = match.participants.length;
            final place = mine?.resultPosition ?? (me == null ? 0 : match.winnerOrder.indexOf(me) + 1);
            final settlement = match.settlement;
            final processing = match.status == 'FINISHING' || settlement == null;
            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 20),
                  CircleAvatar(
                    radius: 38,
                    child: Icon(
                        draw
                            ? Icons.handshake_outlined
                            : won
                                ? Icons.emoji_events_rounded
                                : Icons.sports_esports_rounded,
                        size: 38),
                  ),
                  const SizedBox(height: 18),
                  Text(
                      draw
                          ? 'Draw'
                          : won
                              ? 'Victory'
                              : players > 2 && place > 1
                                  ? '${_ordinal(place)} of $players'
                                  : 'Match complete',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    draw
                        ? 'No winner this time. Stakes are returned to both players.'
                        : won
                            ? 'Your result is confirmed by the server.'
                            : 'The server has confirmed the final result.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  if (match.isPractice)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.smart_toy_outlined),
                        title: Text('Practice game'),
                        subtitle: Text('Free game against the computer. No stake, no stats.'),
                      ),
                    )
                  else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(children: [
                          _ResultRow(label: 'Stake', value: MoneyFormatter.minorToEtb(BigInt.from(match.stakeAmountMinor))),
                          if (settlement != null) ...[
                            _ResultRow(label: 'Pot', value: MoneyFormatter.minorToEtb(BigInt.from(settlement.potAmountMinor))),
                            if (draw)
                              const _ResultRow(label: 'Stakes', value: 'Returned')
                            else ...[
                              _ResultRow(label: 'Platform fee', value: MoneyFormatter.minorToEtb(BigInt.from(settlement.platformFeeMinor))),
                              _ResultRow(
                                  label: 'Winner payout', value: MoneyFormatter.minorToEtb(BigInt.from(settlement.payoutAmountMinor))),
                            ],
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
                            Expanded(
                                child: Text('Result confirmed. Prize settlement is processing…',
                                    style: Theme.of(context).textTheme.bodyMedium)),
                          ]),
                        ),
                      )
                    else
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.verified_rounded),
                          title: Text('Settlement complete'),
                          subtitle: Text('Wallet and ledger were updated by the backend.'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  if (match.isPractice) ...[
                    _PlayAgainCard(gameCode: widget.gameCode),
                    const SizedBox(height: 16),
                  ] else if (match.status == 'FINISHED' && me != null && players == 2) ...[
                    _RematchCard(me: me),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.tonalIcon(
                    onPressed: () => context.go(GameRoutes.lobby(widget.gameCode)),
                    icon: const Icon(Icons.groups_rounded),
                    label: const Text('Find another player'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: () => context.go('/home'), child: const Text('Back to home')),
                  const SizedBox(height: 10),
                  TextButton(onPressed: () => context.push('/history/${widget.matchId}'), child: const Text('View match details')),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _ordinal(int n) => switch (n) {
      2 => '2nd',
      3 => '3rd',
      _ => '${n}th',
    };

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

/// Offer / answer a rematch with the same opponent and stake.
class _RematchCard extends ConsumerWidget {
  const _RematchCard({required this.me});
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rematchControllerProvider);
    final controller = ref.read(rematchControllerProvider.notifier);
    final offer = state.offer;
    final incoming = offer != null && offer.opponentId == me;
    final opponent = offer == null ? null : (incoming ? offer.challengerName : offer.opponentName) ?? 'Your opponent';

    final Widget body;
    if (offer == null) {
      body = FilledButton.icon(
        onPressed: state.busy ? null : controller.request,
        icon: const Icon(Icons.replay_rounded),
        label: const Text('Rematch'),
      );
    } else if (incoming) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$opponent wants a rematch.', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: state.busy ? null : controller.decline, child: const Text('Decline'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton(onPressed: state.busy ? null : controller.accept, child: const Text('Accept'))),
        ]),
      ]);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 12),
          Expanded(child: Text('Waiting for $opponent to accept…')),
        ]),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: state.busy ? null : controller.cancel, child: const Text('Cancel rematch')),
      ]);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          body,
          if (state.message != null) ...[
            const SizedBox(height: 8),
            Text(state.message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}

/// Practice: start another game against the computer (same level by default).
class _PlayAgainCard extends ConsumerWidget {
  const _PlayAgainCard({required this.gameCode});
  final String gameCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(lastPracticeLevelProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton.icon(
            onPressed: () => level == null
                ? showPracticeSheet(context, ref, gameCode: gameCode)
                : startPractice(context, ref, level, gameCode: gameCode),
            icon: const Icon(Icons.replay_rounded),
            label: Text(level == null ? 'Play again' : 'Play again (${level.label})'),
          ),
          if (level != null)
            TextButton(onPressed: () => showPracticeSheet(context, ref, gameCode: gameCode), child: const Text('Change level')),
        ]),
      ),
    );
  }
}
