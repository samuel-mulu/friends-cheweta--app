import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/chat_thread.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/dama/presentation/screens/dama_match_screen.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_type_picker.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/game_grid.dart';
import 'package:friends_game_app/features/karta/presentation/screens/karta_match_screen.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/goal_picker.dart';
import 'package:friends_game_app/features/match/application/practice_launcher.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/widgets/balance_pill.dart';

/// Dama lobbies offer a type (እግረኛ / ታንከኛ) once the catalog has stakes of both.
bool _damaTyped(LiveLobbyState state) =>
    state.gameCode == GameCodes.dama && state.offersAll(DamaType.values.map((type) => type.rulesVersion));

/// The Dama type of a stake, in a lobby that offers types (null otherwise).
DamaType? _typeOf(LiveLobbyState state, GameMode? stake) => _damaTyped(state) ? DamaType.tryParse(stake?.rulesVersion) : null;

/// One game's live lobby: practice, every stake's players (filterable), chat,
/// and the player's own stake + Ready in the thumb zone.
class GameLobbyScreen extends ConsumerStatefulWidget {
  const GameLobbyScreen({super.key, required this.gameCode, this.initialStakeId});
  final String gameCode;

  /// Sit at this stake on open (e.g. from an older "room" link).
  final String? initialStakeId;

  @override
  ConsumerState<GameLobbyScreen> createState() => _GameLobbyScreenState();
}

class _GameLobbyScreenState extends ConsumerState<GameLobbyScreen> {
  late final LiveLobbyController _lobby;
  bool _chat = false;
  bool _opened = false;
  String? _inviteShown;

  @override
  void initState() {
    super.initState();
    _lobby = ref.read(liveLobbyControllerProvider.notifier);
    Future.microtask(_openWhenStakesKnown);
  }

  /// The lobby needs the game's stakes (cached catalog shows them at once).
  void _openWhenStakesKnown() {
    if (!mounted || _opened) return;
    final stakes = ref.read(gameHubControllerProvider).modesFor(widget.gameCode);
    if (stakes.isEmpty) return;
    _opened = true;
    unawaited(_lobby.open(widget.gameCode, stakes: stakes, stakeId: widget.initialStakeId ?? _lastDamaTypeStake(stakes)));
  }

  /// Dama opens on the type played last (ታንከኛ the first time): its smallest stake.
  String? _lastDamaTypeStake(List<GameMode> stakes) {
    if (widget.gameCode != GameCodes.dama) return null;
    final catalog = stakes.where((stake) => !stake.custom).toList();
    final both = DamaType.values.every((type) => catalog.any((stake) => stake.rulesVersion == type.rulesVersion));
    if (!both) return null;
    final type = ref.read(playerPreferencesProvider).damaType;
    final ofType = catalog.where((stake) => stake.rulesVersion == type.rulesVersion).toList()
      ..sort((a, b) => a.stakeAmountMinor.compareTo(b.stakeAmountMinor));
    return ofType.isEmpty ? null : ofType.first.id;
  }

  Future<void> _reloadLobby() async {
    final wasOpened = _opened;
    await ref.read(gameHubControllerProvider.notifier).load();
    if (!mounted || !wasOpened) return;

    final stakes = ref.read(gameHubControllerProvider).modesFor(widget.gameCode);
    final current = ref.read(liveLobbyControllerProvider);
    if (stakes.isNotEmpty) {
      await _lobby.open(widget.gameCode, stakes: stakes, stakeId: current.myStakeId ?? widget.initialStakeId);
    }
  }

  @override
  void dispose() {
    // Lobby membership lives exactly as long as this screen (also on the way
    // into a match; the server already removed us then, so this is a no-op).
    Future.microtask(_lobby.leave);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(gameHubControllerProvider);
    final state = ref.watch(liveLobbyControllerProvider);
    final socket = ref.watch(gameSocketStatusProvider);
    final entry = gameCatalog.firstWhere((e) => e.code == widget.gameCode, orElse: () => gameCatalog.first);

    ref.listen(gameHubControllerProvider, (_, __) => _openWhenStakesKnown());
    // Remember the Dama type played last (switching, or playing someone of the other type).
    ref.listen(liveLobbyControllerProvider.select((s) => s.myRules), (previous, next) {
      if (next == previous) return;
      final lobby = ref.read(liveLobbyControllerProvider);
      final type = _typeOf(lobby, lobby.myStake);
      if (type != null) unawaited(ref.read(playerPreferencesProvider.notifier).setDamaType(type));
    });
    ref.listen(liveLobbyControllerProvider, (previous, next) {
      final matchId = next.acceptedMatchId;
      if (matchId != null && matchId.isNotEmpty && previous?.acceptedMatchId != matchId) {
        context.go(GameRoutes.match(next.acceptedGameCode ?? widget.gameCode, matchId));
      }
      final error = next.error;
      if (error != null && error != previous?.error && next.myStakeId != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
        _lobby.clearError();
      }
      final invite = next.activeChallenge;
      if (invite != null && invite.isInvite && invite.id != _inviteShown) {
        _inviteShown = invite.id;
        unawaited(_showInvite(context));
      }
    });

    final hasStakes = hub.modesFor(widget.gameCode).isNotEmpty;
    final loading = (hub.loading && (!hasStakes || state.myStakeId == null)) || (state.loading && state.players.isEmpty);
    final lobbyError = loading
        ? null
        : !hasStakes
            ? hub.error ?? 'No stakes are available for ${entry.name} right now.'
            : state.gameCode == widget.gameCode && state.myStakeId == null
                ? state.error
                : null;
    final showTabs = hasStakes && lobbyError == null;

    return PopScope(
      canPop: !state.isChallenged && !state.isReady,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (state.isChallenged) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answer the request first.')));
          return;
        }
        if (await _confirmLeaveReady(context) == true && context.mounted) {
          await _lobby.leave();
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(entry.name),
          actions: [
            const BalancePill(),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) => switch (value) {
                'code' => _joinWithCode(context, ref, widget.gameCode),
                'invite' => _invite(context),
                _ => _rules(context),
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'code', child: _MenuRow(Icons.key_rounded, 'Join with a code')),
                const PopupMenuItem(value: 'invite', child: _MenuRow(Icons.person_add_alt_1_rounded, 'Invite a friend')),
                if (widget.gameCode != GameCodes.ludo)
                  const PopupMenuItem(value: 'rules', child: _MenuRow(Icons.menu_book_rounded, 'How to play')),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(children: [
          if (socket != GameSocketStatus.connected) const _ConnectionStrip(),
          if (showTabs)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _Tabs(
                chat: _chat,
                players: state.readyCount,
                unread: state.chatUnread,
                onChanged: (chat) {
                  setState(() => _chat = chat);
                  if (chat) _lobby.clearChatUnread();
                },
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _chat && showTabs
                  ? ChatThread(
                      key: const ValueKey('chat'),
                      lines: [
                        for (final m in state.messages)
                          ChatLine(
                            id: m.id,
                            text: m.text,
                            senderName: m.sender.displayName,
                            mine: m.sender.userId == state.currentUserId,
                            createdAt: m.createdAt,
                          ),
                      ],
                      sending: state.sendingMessage,
                      emptyText: 'No messages yet. Say hello to the lobby.',
                      onSend: _lobby.sendMessage,
                    )
                  : _PlayersPane(
                      key: const ValueKey('players'),
                      gameCode: widget.gameCode,
                      state: state,
                      loading: loading,
                      loadError: lobbyError,
                      onPlay: (player) => _play(context, player),
                      onRefresh: _reloadLobby,
                    ),
            ),
          ),
        ]),
        bottomNavigationBar: showTabs ? _ReadyBar(state: state, onPickStake: () => _pickStake(context)) : null,
      ),
    );
  }

  /// Dama explains both types once both are offered (else every stake is ታንከኛ).
  Future<void> _rules(BuildContext context) => widget.gameCode == GameCodes.karta
      ? showKartaRules(context)
      : showDamaRules(context, type: _damaTyped(ref.read(liveLobbyControllerProvider)) ? null : DamaType.fallback);

  Future<void> _invite(BuildContext context) async {
    final state = ref.read(liveLobbyControllerProvider);
    if (state.activeChallenge != null) return;
    if (widget.gameCode != GameCodes.ludo) return _lobby.createInvite();
    final goal = await pickGoal(context, confirmLabel: 'Create invite');
    if (goal != null) await _lobby.createInvite(tokensToWin: goal);
  }

  /// Ask a ready player to play, at their stake.
  Future<void> _play(BuildContext context, LobbyPlayer player) async {
    final state = ref.read(liveLobbyControllerProvider);
    final theirs = state.stakeById(player.gameModeId);
    final balance = ref.read(walletControllerProvider).wallet?.availableBalance;
    if (theirs != null && balance != null && balance < BigInt.from(theirs.stakeAmountMinor)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('You need ${MoneyFormatter.compactEtb(theirs.stakeAmountMinor)} to play ${player.displayName}.'),
          action: SnackBarAction(label: 'Add funds', onPressed: () => context.push('/deposit')),
        ));
      return;
    }
    if (theirs != null && theirs.id != state.myStakeId) {
      final ok = await _confirmStakeChange(
        context,
        player,
        theirs,
        theirType: _typeOf(state, theirs),
        myType: _typeOf(state, state.myStake),
      );
      if (ok != true || !context.mounted) return;
    }
    HapticFeedback.selectionClick();
    if (widget.gameCode != GameCodes.ludo) return _lobby.challenge(player);
    final goal = await pickGoal(context, confirmLabel: 'Send request');
    if (goal != null) await _lobby.challenge(player, tokensToWin: goal);
  }

  Future<void> _pickStake(BuildContext context) async {
    final state = ref.read(liveLobbyControllerProvider);
    if (state.isChallenged) return;
    final picked = await showAppSheet<String>(context, builder: (_) => _StakeSheet(state: state));
    if (picked == _customStake && context.mounted) return _pickCustomStake(context);
    if (picked != null) await _lobby.changeStake(picked);
  }

  /// Any amount: the stake appears in the lobby for everyone while I sit at it.
  Future<void> _pickCustomStake(BuildContext context) async {
    if (ref.read(liveLobbyControllerProvider).isChallenged) return;
    final amount = await showAppSheet<int>(context, builder: (_) => const _CustomStakeSheet());
    if (amount == null) return;
    // In a typed Dama lobby the custom stake is of the type I play.
    final state = ref.read(liveLobbyControllerProvider);
    await _lobby.playCustomStake(amount, rulesVersion: _damaTyped(state) ? state.myRules : null);
  }

  Future<void> _showInvite(BuildContext context) async {
    await showAppSheet<void>(context, dismissible: false, builder: (_) => const _InviteSheet());
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]);
}

class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: scheme.secondaryContainer,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSecondaryContainer)),
        const SizedBox(width: 10),
        Text('Reconnecting…', style: TextStyle(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}

/// Players / Chat switch.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.chat, required this.players, required this.unread, required this.onChanged});
  final bool chat;
  final int players;
  final int unread;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget tab(String label, bool selected, VoidCallback onTap, {required int count, required String status}) {
      final scheme = Theme.of(context).colorScheme;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          label: count > 0 ? '$label, $count $status' : label,
          excludeSemantics: true,
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scheme.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow:
                    selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))] : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, color: selected ? scheme.onSurface : scheme.onSurfaceVariant),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                    child: Text(count > 99 ? '99+' : '$count',
                        style: TextStyle(color: scheme.onPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: palette.surfaceAlt, borderRadius: BorderRadius.circular(13)),
      child: Row(children: [
        tab('Players', !chat, () => onChanged(false), count: players, status: 'ready'),
        tab('Chat', chat, () => onChanged(true), count: unread, status: 'unread'),
      ]),
    );
  }
}

class _PlayersPane extends StatelessWidget {
  const _PlayersPane({
    super.key,
    required this.gameCode,
    required this.state,
    required this.loading,
    required this.loadError,
    required this.onPlay,
    required this.onRefresh,
  });

  final String gameCode;
  final LiveLobbyState state;
  final bool loading;
  final String? loadError;
  final ValueChanged<LobbyPlayer> onPlay;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final players = state.visiblePlayers;
    final ready = players.where((p) => p.isReady).toList();
    final others = players.where((p) => !p.isReady).toList();
    final canPlay = !state.isChallenged && state.activeChallenge == null && !state.busy && !state.isRecovering;
    final filtered = state.stakeById(state.filterStakeId);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
        if (practiceGameCodes.contains(gameCode))
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            sliver: SliverToBoxAdapter(child: _PracticeRow(gameCode: gameCode)),
          ),
        if (state.visibleStakes.isNotEmpty && loadError == null) SliverToBoxAdapter(child: _StakeFilter(state: state)),
        if (loadError != null)
          SliverToBoxAdapter(child: AppErrorView(message: loadError!, onRetry: onRefresh))
        else if (loading)
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.separated(
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, __) => const Row(children: [
                Skeleton(height: 44, width: 44, radius: 22),
                SizedBox(width: 12),
                Expanded(child: Skeleton(height: 18)),
              ]),
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: 'Ready to play',
                trailing: ready.isEmpty ? null : StatusPill(label: '${ready.length}', tone: StatusTone.live, dot: true),
              ),
            ),
          ),
          if (ready.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.hourglass_empty_rounded,
                title: filtered == null
                    ? 'No one is ready yet'
                    : 'No one is ready at ${_typeOf(state, filtered) == null ? '' : '${_typeOf(state, filtered)!.name} · '}'
                        '${MoneyFormatter.compactEtb(filtered.stakeAmountMinor)}',
                message: state.isReady
                    ? "You're ready. Players who join will see you at the top."
                    : 'Tap "I\'m ready" below so others can play you.',
              ),
            )
          else
            SliverList.builder(
              itemCount: ready.length,
              itemBuilder: (_, i) => _PlayerRow(
                player: ready[i],
                stake: state.stakeById(ready[i].gameModeId),
                type: _typeOf(state, state.stakeById(ready[i].gameModeId)),
                myType: _typeOf(state, state.myStake),
                showStake: state.filterStakeId == null,
                connecting: state.pendingChallengeUserId == ready[i].userId,
                canPlay: canPlay,
                onPlay: () => onPlay(ready[i]),
              ),
            ),
          if (others.isNotEmpty) ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: SectionHeader(title: 'In the lobby · ${others.length}')),
            ),
            SliverList.builder(
              itemCount: others.length,
              itemBuilder: (_, i) => _PlayerRow(
                player: others[i],
                stake: state.stakeById(others[i].gameModeId),
                type: _typeOf(state, state.stakeById(others[i].gameModeId)),
                myType: _typeOf(state, state.myStake),
                showStake: state.filterStakeId == null,
                connecting: false,
                canPlay: false,
                onPlay: () {},
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ]),
    );
  }
}

class _PracticeRow extends ConsumerWidget {
  const _PracticeRow({required this.gameCode});
  final String gameCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showPracticeSheet(context, ref, gameCode: gameCode),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.smart_toy_rounded, color: theme.colorScheme.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Practice with a bot', style: theme.textTheme.titleSmall),
                Text('Free. Warm up before you play for money.', style: theme.textTheme.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

/// "All" plus one chip per stake, with how many are ready at each.
class _StakeFilter extends ConsumerWidget {
  const _StakeFilter({required this.state});
  final LiveLobbyState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(liveLobbyControllerProvider.notifier);
    Widget chip(String label, int ready, bool selected, VoidCallback onTap) {
      final scheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onTap();
          },
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label),
            if (ready > 0) ...[
              const SizedBox(width: 6),
              LiveDot(size: 6, color: selected ? scheme.onPrimary : null),
              const SizedBox(width: 3),
              Text('$ready'),
            ],
          ]),
          labelStyle: TextStyle(
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    return Semantics(
      label: 'Filter players by stake',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          // "All" shows everyone (both Dama types); the amounts are those of my type.
          chip('All stakes', state.readyCount, state.filterStakeId == null, () => controller.setFilter(null)),
          for (final stake in _damaTyped(state) && state.myRules != null ? state.stakesOfRules(state.myRules!) : state.visibleStakes)
            chip(
              MoneyFormatter.compactEtb(stake.stakeAmountMinor),
              state.readyCountAt(stake.id),
              state.filterStakeId == stake.id,
              () => controller.setFilter(stake.id),
            ),
        ]),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.stake,
    required this.showStake,
    required this.connecting,
    required this.canPlay,
    required this.onPlay,
    this.type,
    this.myType,
  });

  final LobbyPlayer player;
  final GameMode? stake;

  /// Dama type of the player's stake (typed Dama lobbies only), and mine.
  final DamaType? type;
  final DamaType? myType;
  final bool showStake;
  final bool connecting;
  final bool canPlay;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (player.state) {
      LobbyPlayerState.ready => _waited(player.readyAt),
      LobbyPlayerState.challenged => 'In a request',
      LobbyPlayerState.online => 'Browsing',
    };
    final messageButton = IconButton(
      tooltip: 'Message ${player.displayName}',
      onPressed: () => context.push('/chats/${player.userId}', extra: player.displayName),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
    );
    final playButton = player.isReady
        ? FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(76, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
            onPressed: canPlay && !connecting ? onPlay : null,
            child: connecting ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Play'),
          )
        : null;
    return Semantics(
      label: '${player.displayName}, ${player.isReady ? 'ready' : status}'
          '${type == null ? '' : ', ${type!.name}'}'
          '${stake == null ? '' : ', ${MoneyFormatter.compactEtb(stake!.stakeAmountMinor)}'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: LayoutBuilder(builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          return Row(children: [
            PlayerAvatar(name: player.displayName, ready: player.isReady),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(player.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                const SizedBox(height: 3),
                Wrap(spacing: 8, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  // Another type than mine stands out: playing them switches my type.
                  if (type != null) DamaTypeTag(type: type!, emphasized: myType != null && type != myType),
                  if (showStake && stake != null) StakePill(amountMinor: stake!.stakeAmountMinor),
                  Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                ]),
              ]),
            ),
            if (playButton != null && constraints.maxWidth < 280 * textScale)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [playButton, messageButton]),
              )
            else ...[
              messageButton,
              if (playButton != null) playButton,
            ],
          ]);
        }),
      ),
    );
  }

  static String _waited(DateTime? readyAt) {
    if (readyAt == null) return 'Ready';
    final minutes = DateTime.now().toUtc().difference(readyAt.toUtc()).inMinutes;
    return minutes < 1 ? 'Ready now' : 'Ready ${minutes}m';
  }
}

/// The player's own stake and Ready, in the thumb zone.
class _ReadyBar extends ConsumerWidget {
  const _ReadyBar({required this.state, required this.onPickStake});
  final LiveLobbyState state;
  final VoidCallback onPickStake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final controller = ref.read(liveLobbyControllerProvider.notifier);
    final stake = state.myStake;
    final balance = ref.watch(walletControllerProvider.select((s) => s.wallet?.availableBalance));
    final affordable = stake == null || balance == null || balance >= BigInt.from(stake.stakeAmountMinor);
    final locked = state.busy || state.isRecovering || state.isChallenged;
    final typed = _damaTyped(state);

    final Widget action;
    if (!affordable) {
      action = FilledButton.icon(
        onPressed: () => context.push('/deposit'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add funds'),
      );
    } else if (state.isReady) {
      action = OutlinedButton.icon(
        onPressed: locked ? null : controller.unready,
        style: OutlinedButton.styleFrom(side: BorderSide(color: palette.live, width: 1.5), foregroundColor: palette.live),
        icon: LiveDot(color: palette.live),
        label: const Text("You're ready · Stop"),
      );
    } else {
      action = FilledButton(
        onPressed: locked || stake == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                controller.ready();
              },
        child:
            state.busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text("I'm ready"),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Dama: choose the game type first, in the thumb zone with the stake.
            if (typed) ...[
              DamaTypePicker(
                compact: true,
                selected: DamaType.tryParse(state.myRules),
                readyCounts: {for (final type in DamaType.values) type: state.readyCountOfRules(type.rulesVersion)},
                enabled: !locked,
                onChanged: (type) => controller.switchRules(type.rulesVersion),
              ),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Semantics(
                button: true,
                label: 'Your stake ${stake == null ? '' : MoneyFormatter.compactEtb(stake.stakeAmountMinor)}. Change stake',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: state.isChallenged ? null : onPickStake,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('Your stake', style: theme.textTheme.labelSmall),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          stake == null ? '—' : MoneyFormatter.compactEtb(stake.stakeAmountMinor),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: palette.money,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Icon(Icons.expand_more_rounded, color: theme.colorScheme.onSurfaceVariant),
                      ]),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: action),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Choose the stake to play for.
class _StakeSheet extends ConsumerWidget {
  const _StakeSheet({required this.state});
  final LiveLobbyState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final balance = ref.watch(walletControllerProvider.select((s) => s.wallet?.availableBalance));
    // A typed Dama lobby lists the stakes of the type I play (switch type in the bar).
    final type = _typeOf(state, state.myStake);
    final stakes = type == null ? state.visibleStakes : state.stakesOfRules(type.rulesVersion);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Choose your stake', style: theme.textTheme.titleLarge)),
        if (type != null) DamaTypeTag(type: type, emphasized: true, large: true),
      ]),
      const SizedBox(height: 4),
      Text('Both players put in the stake. The winner takes the prize.', style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => Navigator.pop(context, _customStake),
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Custom stake'),
      ),
      const SizedBox(height: 16),
      for (final stake in stakes) ...[
        Builder(builder: (context) {
          final selected = stake.id == state.myStakeId;
          final affordable = balance == null || balance >= BigInt.from(stake.stakeAmountMinor);
          final ready = state.readyCountAt(stake.id);
          return Material(
            color: selected ? theme.colorScheme.primaryContainer : palette.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: affordable ? () => Navigator.pop(context, stake.id) : null,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        MoneyFormatter.compactEtb(stake.stakeAmountMinor),
                        style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        affordable
                            ? 'Winner gets ${MoneyFormatter.compactEtb(stake.estimatedWinnerPayoutMinor)} · ${stake.turnDurationSeconds}s turns'
                            : 'Add funds to play this stake',
                        style: theme.textTheme.bodySmall,
                      ),
                    ]),
                  ),
                  if (ready > 0) ...[StatusPill(label: '$ready ready', tone: StatusTone.live, dot: true), const SizedBox(width: 8)],
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  ),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

/// Picked in [_StakeSheet] to type an amount instead.
const _customStake = '__custom__';

const _customMinEtb = 5;
const _customMaxEtb = 10000;

/// Type any whole amount (5 to 10,000 ETB) up to the balance.
class _CustomStakeSheet extends ConsumerStatefulWidget {
  const _CustomStakeSheet();

  @override
  ConsumerState<_CustomStakeSheet> createState() => _CustomStakeSheetState();
}

class _CustomStakeSheetState extends ConsumerState<_CustomStakeSheet> {
  final _amount = TextEditingController();

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final balanceMinor = ref.watch(walletControllerProvider.select((s) => s.wallet?.availableBalance))?.toInt();
    final balanceEtb = balanceMinor == null ? null : balanceMinor ~/ 100;
    final stakes = ref.read(liveLobbyControllerProvider).stakes;
    final feeBps = stakes.isEmpty ? 0 : stakes.first.platformFeeBps;

    final etb = int.tryParse(_amount.text);
    final String? problem = switch (etb) {
      null => null,
      final value when value < _customMinEtb => 'The smallest stake is $_customMinEtb ETB.',
      final value when value > _customMaxEtb => 'The largest stake is ${MoneyFormatter.compactEtb(_customMaxEtb * 100)}.',
      final value when balanceEtb != null && value > balanceEtb => 'Your balance is ${MoneyFormatter.compactEtb(balanceMinor!)}.',
      _ => null,
    };
    final valid = etb != null && problem == null;
    final prizeMinor = valid ? etb * 100 * 2 - (etb * 100 * 2 * feeBps ~/ 10000) : null;

    final quick = [100, 200, 500, 1000].where((v) => balanceEtb == null || v <= balanceEtb).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Play for any amount', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        'Your stake shows in the lobby for everyone. Anyone ready at this amount can play you.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _amount,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        decoration: InputDecoration(
          hintText: '0',
          suffixText: 'ETB',
          errorText: problem,
          helperText: balanceMinor == null ? null : 'Balance ${MoneyFormatter.compactEtb(balanceMinor)}',
        ),
      ),
      if (quick.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final value in quick)
            ActionChip(
              label: Text('$value ETB'),
              onPressed: () => _amount.text = '$value',
            ),
        ]),
      ],
      const SizedBox(height: 16),
      AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: prizeMinor == null ? 0 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: palette.moneyTint, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(child: Text('Winner gets', style: theme.textTheme.bodyMedium)),
            Text(
              prizeMinor == null ? '' : MoneyFormatter.compactEtb(prizeMinor),
              style: theme.textTheme.titleMedium?.copyWith(color: palette.money, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: valid ? () => Navigator.pop(context, etb * 100) : null,
        child: Text(valid ? 'Play for ${MoneyFormatter.compactEtb(etb * 100)}' : 'Enter an amount'),
      ),
      if (balanceMinor != null && balanceEtb! < _customMinEtb) ...[
        const SizedBox(height: 8),
        TextButton(onPressed: () => context.push('/deposit'), child: const Text('Add funds')),
      ],
    ]);
  }
}

/// My open invite: the code to share, its countdown, and cancel.
class _InviteSheet extends ConsumerWidget {
  const _InviteSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveLobbyControllerProvider);
    final invite = state.activeChallenge;
    final theme = Theme.of(context);
    ref.listen(liveLobbyControllerProvider.select((s) => s.activeChallenge?.id), (previous, next) {
      if (previous != null && next != previous && Navigator.canPop(context)) Navigator.pop(context);
    });
    if (invite == null || !invite.isInvite) {
      return const SizedBox(height: 80);
    }
    final code = invite.displayInviteCode ?? '';
    final stake = state.stakeById(invite.gameModeId);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Invite a friend', style: theme.textTheme.titleLarge)),
        CountdownRing(expiresAt: invite.expiresAt, total: invite.expiresAt.difference(invite.createdAt), size: 44),
      ]),
      const SizedBox(height: 6),
      Text(
        'Send this code to your friend. They enter it under "Got a code from a friend?" and the match starts.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 18),
      Material(
        color: AppPalette.of(context).surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _copy(context, code),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Text(
                  code,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 3, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              const Icon(Icons.copy_rounded),
            ]),
          ),
        ),
      ),
      if (stake != null) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_typeOf(state, stake) case final type?) ...[DamaTypeTag(type: type, emphasized: true), const SizedBox(width: 8)],
          StakePill(amountMinor: stake.stakeAmountMinor, prefix: 'Stake'),
          const SizedBox(width: 8),
          StakePill(amountMinor: stake.estimatedWinnerPayoutMinor, prefix: 'Prize'),
        ]),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: () => _copy(context, code), icon: const Icon(Icons.copy_rounded), label: const Text('Copy code')),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: state.busy ? null : () => ref.read(liveLobbyControllerProvider.notifier).cancel(),
        child: Text(state.busy ? 'Cancelling…' : 'Cancel invite'),
      ),
    ]);
  }

  void _copy(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code.replaceAll('-', '')));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Code copied')));
  }
}

/// Playing someone at another stake (and, in Dama, maybe another type) moves me there.
Future<bool?> _confirmStakeChange(
  BuildContext context,
  LobbyPlayer player,
  GameMode stake, {
  DamaType? theirType,
  DamaType? myType,
}) {
  final theme = Theme.of(context);
  // The type I switch to, when it differs from mine.
  final DamaType? newType = theirType != null && theirType != myType ? theirType : null;
  return showAppSheet<bool>(
    context,
    builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'Play ${player.displayName}${newType != null ? ' · ${newType.name}' : ''} for ${MoneyFormatter.compactEtb(stake.stakeAmountMinor)}?',
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        newType != null
            ? '${player.displayName} plays ${newType.name}: ${newType.captureRule.toLowerCase()} '
                'Your game type and stake change to match.'
            : '${player.displayName} is ready at a different stake. Your stake changes to match.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      if (newType != null) ...[
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (myType != null) ...[
            DamaTypeTag(type: myType, large: true),
            Icon(Icons.arrow_forward_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
          DamaTypeTag(type: newType, emphasized: true, large: true),
        ]),
        const SizedBox(height: 10),
      ],
      Row(children: [
        StakePill(amountMinor: stake.stakeAmountMinor, prefix: 'Stake', large: true),
        const SizedBox(width: 8),
        StakePill(amountMinor: stake.estimatedWinnerPayoutMinor, prefix: 'Prize', large: true),
      ]),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text('Play for ${MoneyFormatter.compactEtb(stake.stakeAmountMinor)}'),
      ),
      const SizedBox(height: 8),
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
    ]),
  );
}

Future<bool?> _confirmLeaveReady(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the lobby?'),
        content: const Text('Other players will no longer see you as ready.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave')),
        ],
      ),
    );

/// Enter a friend's invite code; joining starts the match.
Future<void> _joinWithCode(BuildContext context, WidgetRef ref, String gameCode) async {
  final joined = await showAppSheet<({String matchId, String? gameCode})>(context, builder: (_) => const _JoinCodeSheet());
  // The code decides the game (a friend may have sent a code for another game).
  if (joined != null && context.mounted) context.go(GameRoutes.match(joined.gameCode ?? gameCode, joined.matchId));
}

/// Shared with Home: open the "join with a code" sheet from anywhere.
Future<void> showJoinWithCode(BuildContext context, WidgetRef ref) => _joinWithCode(context, ref, GameCodes.ludo);

class _JoinCodeSheet extends ConsumerStatefulWidget {
  const _JoinCodeSheet();
  @override
  ConsumerState<_JoinCodeSheet> createState() => _JoinCodeSheetState();
}

class _JoinCodeSheetState extends ConsumerState<_JoinCodeSheet> {
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
      final joined = await ref.read(liveLobbyControllerProvider.notifier).joinInvite(_code.text.replaceAll('-', ''));
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Join with a code', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text('Enter the code your friend sent. The match starts right away.', style: theme.textTheme.bodySmall),
      const SizedBox(height: 16),
      TextField(
        controller: _code,
        autofocus: true,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 3),
        decoration: InputDecoration(hintText: 'ABCDE-FGHJK', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text('Join match'),
      ),
    ]);
  }
}

/// Square art for a game (kept for the result screen and others).
Widget gameHeroArt(String gameCode) => GameArt(code: gameCode);
