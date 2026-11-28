import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_theme.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/karta/application/karta_table_controller.dart';
import 'package:friends_game_app/features/karta/domain/karta_table.dart';
import 'package:friends_game_app/features/karta/presentation/screens/karta_match_screen.dart';
import 'package:friends_game_app/features/karta/presentation/widgets/karta_cards.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_back_guard.dart';

/// A Karta queue table: who sits where (starter, receiver, the queue), the
/// stake per round (the two players may raise it), and the round in play.
/// Players waiting in the queue watch the round; every round pays at once.
class KartaTableScreen extends ConsumerStatefulWidget {
  const KartaTableScreen({super.key});

  @override
  ConsumerState<KartaTableScreen> createState() => _KartaTableScreenState();
}

class _KartaTableScreenState extends ConsumerState<KartaTableScreen> with WidgetsBindingObserver {
  /// The round on the board: the current one, or the one that just ended
  /// (its result stays up during the pause before the next round).
  String? _boardMatchId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(kartaTableControllerProvider.notifier).load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(ref.read(kartaTableControllerProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(kartaTableControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    final table = view.table;

    ref.listen(kartaTableControllerProvider, (previous, next) {
      final ended = next.endedReason;
      if (ended != null && previous?.endedReason != ended) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(tableEndedText(ended))));
        context.go(GameRoutes.lobby(GameCodes.karta));
        return;
      }
      final error = next.error;
      if (error != null && error != previous?.error && next.table != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
        ref.read(kartaTableControllerProvider.notifier).clearError();
      }
      // A raise the other player of my round asked for: answer it.
      final raise = next.table?.raise;
      if (raise != null && raise != previous?.table?.raise && raise.byUserId != me && next.table!.inRound(me)) {
        HapticFeedback.mediumImpact();
      }
    });

    if (table?.matchId != null) _boardMatchId = table!.matchId;
    final boardId = _boardMatchId;

    return MatchBackGuard(
      onBack: () => _leave(table),
      child: Theme(
        data: AppTheme.dark(),
        child: Scaffold(
          backgroundColor: KartaPalette.feltBottom,
          body: table == null
              ? Center(
                  child: view.error == null
                      ? const CircularProgressIndicator()
                      : Column(mainAxisSize: MainAxisSize.min, children: [
                          Padding(padding: const EdgeInsets.all(24), child: Text(view.error!, textAlign: TextAlign.center)),
                          FilledButton(onPressed: () => ref.read(kartaTableControllerProvider.notifier).load(), child: const Text('Try again')),
                          TextButton(onPressed: () => context.go(GameRoutes.lobby(GameCodes.karta)), child: const Text('Back to the lobby')),
                        ]),
                )
              : Column(children: [
                  SafeArea(
                    bottom: false,
                    child: TableStrip(
                      table: table,
                      me: me,
                      busy: view.busy,
                      onRaise: () => _raise(table),
                      onAnswer: (accept) => ref.read(kartaTableControllerProvider.notifier).answerRaise(accept),
                    ),
                  ),
                  Expanded(
                    child: boardId == null
                        ? const Center(child: Text('Seating the next round…', style: TextStyle(color: Colors.white70)))
                        : MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            child: KartaMatchScreen(
                              key: ValueKey(boardId),
                              matchId: boardId,
                              tableMode: true,
                              onLeaveTable: () => _leave(table),
                            ),
                          ),
                  ),
                ]),
        ),
      ),
    );
  }

  /// Back or the exit button: leave the table (in a round, it is lost).
  Future<void> _leave(KartaTable? table) async {
    final me = ref.read(authControllerProvider).user?.id;
    if (table == null) {
      context.go(GameRoutes.lobby(GameCodes.karta));
      return;
    }
    final inRound = table.inRound(me);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(inRound ? 'Leave the table?' : 'Leave the queue?'),
        content: Text(inRound
            ? 'You are playing this round: leaving loses its stake (${MoneyFormatter.compactEtb(table.stakeMinor)}).'
            : 'You are waiting your turn, so nothing is taken from your wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Wait')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(kartaTableControllerProvider.notifier).leave();
  }

  /// The higher catalog stakes of Karta, to raise the stake to.
  Future<void> _raise(KartaTable table) async {
    final amounts = {
      for (final mode in ref.read(gameHubControllerProvider).modesFor(GameCodes.karta))
        if (!mode.custom && mode.stakeAmountMinor > table.stakeMinor) mode.stakeAmountMinor,
    }.toList()
      ..sort();
    if (amounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This is already the highest stake.')));
      return;
    }
    final amount = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Raise the stake'),
            subtitle: Text('From the next round, if the other player agrees.'),
          ),
          for (final value in amounts)
            ListTile(
              leading: const Icon(Icons.trending_up_rounded),
              title: Text(MoneyFormatter.compactEtb(value), style: AppType.money(size: 18)),
              onTap: () => Navigator.pop(sheet, value),
            ),
        ]),
      ),
    );
    if (amount != null && mounted) await ref.read(kartaTableControllerProvider.notifier).raise(amount);
  }
}

/// Seats in turn order (STARTER, RECEIVER, 1st, 2nd…), the stake per round,
/// Raise for the two players of the round, and the raise to answer.
class TableStrip extends StatelessWidget {
  const TableStrip({
    super.key,
    required this.table,
    required this.me,
    required this.busy,
    required this.onRaise,
    required this.onAnswer,
  });

  final KartaTable table;
  final String? me;
  final bool busy;
  final VoidCallback onRaise;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final raise = table.raise;
    final myRole = table.roleOf(me);
    final place = table.queuePlace(me);
    final status = switch (myRole) {
      KartaSeatRole.starter => table.isPlaying ? 'You deal this round' : 'You won: you deal next',
      KartaSeatRole.receiver => 'You receive this round',
      KartaSeatRole.waiting => place == 1 ? 'You play next · watching' : "You're ${_ordinal(place)} in line · watching",
      KartaSeatRole.none => '',
    };
    final last = table.last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.table_restaurant_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Round ${table.round} · ${table.seated}/${table.maxSeats}',
              style: AppType.ui(size: 14, weight: FontWeight.w700, color: Colors.white),
            ),
          ),
          Semantics(
            label: 'Stake per round ${MoneyFormatter.compactEtb(table.stakeMinor)}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.gold)),
              child: Text(MoneyFormatter.compactEtb(table.stakeMinor), style: AppType.money(size: 15, color: AppColors.gold)),
            ),
          ),
          if (table.inRound(me) && raise == null) ...[
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Raise the stake',
              visualDensity: VisualDensity.compact,
              onPressed: busy ? null : onRaise,
              icon: const Icon(Icons.trending_up_rounded, color: Colors.white),
            ),
          ],
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final player in table.players)
              _SeatChip(
                name: player.userId == me ? 'You' : player.fullName.split(' ').first,
                label: switch (table.roleOf(player.userId)) {
                  KartaSeatRole.starter => 'STARTER',
                  KartaSeatRole.receiver => 'RECEIVER',
                  _ => _ordinal(table.queuePlace(player.userId)).toUpperCase(),
                },
                active: table.inRound(player.userId) || (!table.isPlaying && player.userId == table.starterId),
                mine: player.userId == me,
              ),
            for (var i = 0; i < table.freeSeats; i++) const _SeatChip(name: 'Free', label: 'SEAT', active: false, mine: false, empty: true),
          ]),
        ),
        if (status.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(status, style: AppType.ui(size: 13, weight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.8))),
        ],
        if (!table.isPlaying && last != null) ...[
          const SizedBox(height: 4),
          Text(
            '${last.winnerId == me ? 'You' : table.nameOf(last.winnerId)} won round ${last.round} · +${MoneyFormatter.compactEtb(last.payoutMinor)}',
            style: AppType.ui(size: 13, weight: FontWeight.w700, color: AppColors.gold),
          ),
        ],
        if (raise != null) ...[
          const SizedBox(height: 8),
          _RaiseBanner(table: table, raise: raise, me: me, busy: busy, onAnswer: onAnswer),
        ],
      ]),
    );
  }

  static String _ordinal(int n) => switch (n) {
        1 => '1st',
        2 => '2nd',
        3 => '3rd',
        _ => '${n}th',
      };
}

class _SeatChip extends StatelessWidget {
  const _SeatChip({required this.name, required this.label, required this.active, required this.mine, this.empty = false});
  final String name;
  final String label;
  final bool active;
  final bool mine;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final border = active ? AppColors.gold : Colors.white.withValues(alpha: empty ? 0.15 : 0.3);
    return Semantics(
      label: '$name, $label',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(minWidth: 72),
        decoration: BoxDecoration(
          color: mine ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: active ? 1.5 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: AppType.ui(size: 10, weight: FontWeight.w800, color: active ? AppColors.gold : Colors.white60)),
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.ui(size: 13, weight: FontWeight.w700, color: empty ? Colors.white38 : Colors.white),
          ),
        ]),
      ),
    );
  }
}

/// The other player asked for a higher stake: Accept / Decline (others see it).
class _RaiseBanner extends StatelessWidget {
  const _RaiseBanner({required this.table, required this.raise, required this.me, required this.busy, required this.onAnswer});
  final KartaTable table;
  final KartaTableRaise raise;
  final String? me;
  final bool busy;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final amount = MoneyFormatter.compactEtb(raise.amountMinor);
    final mine = raise.byUserId == me;
    final mayAnswer = !mine && table.inRound(me);
    final text = mine
        ? 'You asked to raise to $amount from the next round.'
        : mayAnswer
            ? '${table.nameOf(raise.byUserId)} asks to raise to $amount from the next round.'
            : 'Stake may rise to $amount from the next round.';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      // Text on its own line, the answer below: fits a narrow phone.
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: AppType.ui(size: 13, weight: FontWeight.w600, color: Colors.white)),
        if (mayAnswer)
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: busy ? null : () => onAnswer(false), child: const Text('Decline')),
            const SizedBox(width: 8),
            FilledButton(onPressed: busy ? null : () => onAnswer(true), child: const Text('Accept')),
          ]),
      ]),
    );
  }
}
