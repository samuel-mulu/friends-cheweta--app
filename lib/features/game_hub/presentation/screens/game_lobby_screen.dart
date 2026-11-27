import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_motion.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/core/widgets/token_hop_loader.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/chat_thread.dart';
import 'package:friends_game_app/features/dama/presentation/screens/dama_match_screen.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/variant_picker.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/game_grid.dart';
import 'package:friends_game_app/features/karta/presentation/screens/karta_match_screen.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';
import 'package:friends_game_app/features/match/application/practice_launcher.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';
import 'package:friends_game_app/features/wallet/presentation/widgets/balance_pill.dart';

/// A lobby offers a type picker and type badges once two or more of its game's
/// types have stakes (Dama እግረኛ / ታንከኛ; Ludo መመለስ ያለበት / የሌለበት / የረሳ ይሸነፋል).
bool _typed(LiveLobbyState state) => state.offeredVariants.length > 1;

/// The type of a stake, in a lobby that offers types (null otherwise).
GameVariant? _typeOf(LiveLobbyState state, GameMode? stake) => _typed(state) ? GameVariants.find(stake?.rulesVersion) : null;

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
    unawaited(_lobby.open(widget.gameCode, stakes: stakes, stakeId: widget.initialStakeId ?? _lastVariantStake(stakes)));
  }

  /// A game with types opens on the type played last (its classic type the
  /// first time): that type's smallest stake. Null: the server's default.
  String? _lastVariantStake(List<GameMode> stakes) {
    final catalog = stakes.where((stake) => !stake.custom).toList();
    final offered = GameVariants.of(widget.gameCode).where((v) => catalog.any((s) => s.rulesVersion == v.rulesVersion));
    if (offered.length < 2) return null;
    final variant = ref.read(playerPreferencesProvider).variantFor(widget.gameCode);
    final ofType = catalog.where((stake) => stake.rulesVersion == variant?.rulesVersion).toList()
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
      if (type != null) unawaited(ref.read(playerPreferencesProvider.notifier).setVariant(type));
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

    // Back goes one step: to the screen below, or Home when the lobby was
    // opened on its own (after a match); never out of the app from here.
    final hasScreenBelow = context.canPop();
    return PopScope(
      canPop: !state.isChallenged && !state.isReady && hasScreenBelow,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (state.isChallenged) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Answer the request first.')));
          return;
        }
        if (state.isReady) {
          if (await _confirmLeaveReady(context) != true || !context.mounted) return;
          await _lobby.leave();
          if (!context.mounted) return;
        }
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(entry.name),
          actions: [
            if (practiceGameCodes.contains(widget.gameCode))
              IconButton(
                tooltip: 'Practice with a bot (free)',
                onPressed: () => showPracticeSheet(context, ref, gameCode: widget.gameCode),
                icon: const Icon(Icons.smart_toy_outlined),
              ),
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
                if (widget.gameCode != GameCodes.ludo) const PopupMenuItem(value: 'rules', child: _MenuRow(Icons.menu_book_rounded, 'How to play')),
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
                  _lobby.setChatOpen(chat);
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
        // The thumb zone: type, stake and the one gold action.
        bottomNavigationBar: showTabs ? _Composer(state: state, onOtherAmount: () => _pickCustomStake(context)) : null,
      ),
    );
  }

  /// Dama explains both types once both are offered (else every stake is ታንከኛ);
  /// Ludo lists its types.
  Future<void> _rules(BuildContext context) => switch (widget.gameCode) {
        GameCodes.karta => showKartaRules(context),
        GameCodes.ludo => showGameTypes(context, GameCodes.ludo),
        _ => showDamaRules(context, variant: _typed(ref.read(liveLobbyControllerProvider)) ? null : GameVariants.damaClassic),
      };

  /// An invite plays my stake and (Ludo) the goal chosen in the ready panel.
  Future<void> _invite(BuildContext context) async {
    final state = ref.read(liveLobbyControllerProvider);
    if (state.activeChallenge != null) return;
    if (widget.gameCode != GameCodes.ludo) return _lobby.createInvite();
    await _lobby.createInvite(tokensToWin: ref.read(playerPreferencesProvider).tokensToWin);
  }

  /// Ask a ready player to play, on their terms: their stake (so their type)
  /// and, in Ludo, their goal. Confirm first when that differs from mine.
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
    final myGoal = ref.read(playerPreferencesProvider).tokensToWin;
    final theirGoal = widget.gameCode == GameCodes.ludo ? player.tokensToWin : null;
    final goalDiffers = theirGoal != null && theirGoal != myGoal;
    if (theirs != null && (theirs.id != state.myStakeId || goalDiffers)) {
      final ok = await _confirmStakeChange(
        context,
        player,
        theirs,
        theirType: _typeOf(state, theirs),
        myType: _typeOf(state, state.myStake),
        theirGoal: goalDiffers ? theirGoal : null,
      );
      if (ok != true || !context.mounted) return;
    }
    HapticFeedback.selectionClick();
    await _lobby.challenge(player, tokensToWin: theirGoal);
  }

  /// Any amount: the stake appears in the lobby for everyone while I sit at it.
  Future<void> _pickCustomStake(BuildContext context) async {
    if (ref.read(liveLobbyControllerProvider).isChallenged) return;
    final amount = await showAppSheet<int>(context, builder: (_) => const _CustomStakeSheet());
    if (amount == null) return;
    // In a typed Dama lobby the custom stake is of the type I play.
    final state = ref.read(liveLobbyControllerProvider);
    await _lobby.playCustomStake(amount, rulesVersion: _typed(state) ? state.myRules : null);
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
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: palette.surfaceAlt,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)),
        const SizedBox(width: 10),
        Text('Reconnecting…', style: AppType.ui(size: 13.5, weight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
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
    final scheme = Theme.of(context).colorScheme;
    // Ready players count in green (live); unread chat is a red badge.
    Widget tab(String label, bool selected, VoidCallback onTap, {required int count, required String status, required bool live}) {
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
              duration: AppMotion.state,
              curve: AppMotion.curve,
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.surfaceAlt : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.ui(size: 15, weight: FontWeight.w600, color: selected ? scheme.onSurface : scheme.onSurfaceVariant),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: live ? palette.liveTint : AppColors.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: AppType.ui(size: 12, weight: FontWeight.w700, color: live ? palette.live : Colors.white),
                    ),
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
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.border),
      ),
      child: Row(children: [
        tab('Players', !chat, () => onChanged(false), count: players, status: 'ready', live: true),
        tab('Chat', chat, () => onChanged(true), count: unread, status: 'unread', live: false),
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
                message: state.isReady ? "You're ready. Players who join will see you at the top." : 'Tap "I\'m ready" below so others can play you.',
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'In the lobby',
                  trailing: StatusPill(label: '${others.length}', tone: StatusTone.muted),
                ),
              ),
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

/// "All" plus one chip per stake, with how many are ready at each.
class _StakeFilter extends ConsumerWidget {
  const _StakeFilter({required this.state});
  final LiveLobbyState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(liveLobbyControllerProvider.notifier);
    // A filter is a view, not a choice of money: the selected chip is ink, not gold.
    Widget chip(String label, int ready, bool selected, VoidCallback onTap, {bool amount = true}) {
      final scheme = Theme.of(context).colorScheme;
      final palette = AppPalette.of(context);
      final fg = selected ? scheme.surface : scheme.onSurface;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: selected,
          label: ready > 0 ? '$label, $ready ready' : label,
          excludeSemantics: true,
          child: Material(
            color: selected ? scheme.onSurface : Colors.transparent,
            shape: StadiumBorder(side: BorderSide(color: selected ? scheme.onSurface : palette.border)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                HapticFeedback.selectionClick();
                onTap();
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label, style: amount ? AppType.money(size: 16, color: fg) : AppType.ui(size: 14, weight: FontWeight.w600, color: fg)),
                  if (ready > 0) ...[
                    const SizedBox(width: 6),
                    LiveDot(size: 6, color: palette.live),
                    const SizedBox(width: 3),
                    Text('$ready', style: AppType.ui(size: 13, weight: FontWeight.w700, color: fg)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Filter players by stake',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          // "All" shows everyone (both Dama types); the amounts are those of my type.
          chip('All stakes', state.readyCount, state.filterStakeId == null, () => controller.setFilter(null), amount: false),
          for (final stake in _typed(state) && state.myRules != null ? state.stakesOfRules(state.myRules!) : state.visibleStakes)
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

  /// Type of the player's stake (lobbies offering types only), and mine.
  final GameVariant? type;
  final GameVariant? myType;
  final bool showStake;
  final bool connecting;
  final bool canPlay;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final status = switch (player.state) {
      LobbyPlayerState.ready => _waited(player.readyAt),
      LobbyPlayerState.challenged => 'In a request',
      LobbyPlayerState.online => 'Browsing',
    };
    final messageButton = IconButton(
      tooltip: 'Message ${player.displayName}',
      onPressed: () => context.push('/chats/${player.userId}', extra: player.displayName),
      icon: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
    );
    // Outlined gold: the screen's one filled gold button is "I'm ready".
    final playButton = player.isReady
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(72, 40),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(color: canPlay ? AppColors.gold : palette.border, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: AppType.ui(size: 15, weight: FontWeight.w700),
            ),
            onPressed: canPlay && !connecting ? onPlay : null,
            child:
                connecting ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold)) : const Text('Play'),
          )
        : null;
    return Semantics(
      label: '${player.displayName}, ${player.isReady ? 'ready' : status}'
          '${type == null ? '' : ', ${type!.name}'}'
          '${stake == null ? '' : ', ${MoneyFormatter.compactEtb(stake!.stakeAmountMinor)}'}',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.surfaceAlt))),
        child: LayoutBuilder(builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          return Row(children: [
            PlayerAvatar(name: player.displayName, ready: player.isReady),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(player.displayName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  // Another type than mine stands out: playing them switches my type.
                  if (type != null) VariantTag(variant: type!, emphasized: myType != null && type != myType),
                  // Ludo: the goal they play (first to N home).
                  if (player.tokensToWin != null) GoalCrowns(goal: player.tokensToWin!),
                  if (showStake && stake != null)
                    Text(MoneyFormatter.compactEtb(stake!.stakeAmountMinor), style: AppType.money(size: 16, color: palette.money)),
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

/// The thumb zone.
///
/// Not ready: choose the game type (when the game has several), the Ludo
/// goal, the stake and auto-match, then one gold "I'm ready". Ready: the
/// panel folds into a short waiting bar showing what I asked for, so the
/// players list gets the room; Edit stops waiting and opens the choices again
/// (change anything, then get ready again).
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.state, required this.onOtherAmount});
  final LiveLobbyState state;
  final VoidCallback onOtherAmount;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  /// Folded by the arrow: one line (choices: what I picked and "I'm ready";
  /// waiting: just that I'm waiting) so the list gets the room.
  bool _folded = false;

  static bool _waiting(LiveLobbyState state) => state.isReady || state.isChallenged;

  @override
  void didUpdateWidget(covariant _Composer old) {
    super.didUpdateWidget(old);
    // Getting ready or tapping Edit opens the panel fresh.
    if (_waiting(old.state) != _waiting(widget.state)) _folded = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final state = widget.state;
    final waiting = _waiting(state);
    return AnimatedSize(
      duration: AppMotion.sheet,
      curve: AppMotion.curve,
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: waiting ? palette.live.withValues(alpha: 0.5) : palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _FoldArrow(folded: _folded, onTap: () => setState(() => _folded = !_folded)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: waiting ? _WaitingBar(state: state, folded: _folded) : _ReadyChoices(state: state, onOtherAmount: widget.onOtherAmount, folded: _folded),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The small arrow on top of the lobby panel: hide or show it.
class _FoldArrow extends StatelessWidget {
  const _FoldArrow({required this.folded, required this.onTap});
  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Semantics(
        button: true,
        label: folded ? 'Show the panel' : 'Hide the panel',
        excludeSemantics: true,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 64,
            height: 28,
            child: AnimatedRotation(
              turns: folded ? 0.5 : 0,
              duration: AppMotion.state,
              curve: AppMotion.curve,
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 24, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Everything to choose before getting ready, and the gold "I'm ready".
class _ReadyChoices extends ConsumerWidget {
  const _ReadyChoices({required this.state, required this.onOtherAmount, this.folded = false});
  final LiveLobbyState state;
  final VoidCallback onOtherAmount;

  /// One line: what I picked, and the gold action.
  final bool folded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final controller = ref.read(liveLobbyControllerProvider.notifier);
    final prefs = ref.watch(playerPreferencesProvider);
    final preferences = ref.read(playerPreferencesProvider.notifier);
    final isLudo = state.gameCode == GameCodes.ludo;
    final stake = state.myStake;
    final balance = ref.watch(walletControllerProvider.select((s) => s.wallet?.availableBalance));
    bool canCover(GameMode mode) => balance == null || balance >= BigInt.from(mode.stakeAmountMinor);
    final affordable = stake == null || canCover(stake);
    final locked = state.busy || state.isRecovering;
    final typed = _typed(state);

    // Catalog stakes of my type, plus the custom amount I sit at.
    final stakes = [
      for (final mode in typed && state.myRules != null ? state.stakesOfRules(state.myRules!) : state.visibleStakes)
        if (!mode.custom || mode.id == state.myStakeId) mode,
    ];

    // Full width in the panel; sized to its label on the folded line.
    final ButtonStyle? actionStyle =
        folded ? FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 18)) : null;
    final Widget action = !affordable
        ? FilledButton.icon(
            style: actionStyle,
            onPressed: () => context.push('/deposit'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add funds'),
          )
        : FilledButton(
            style: actionStyle,
            onPressed: locked || stake == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    controller.ready(tokensToWin: isLudo ? prefs.tokensToWin : null, autoMatch: prefs.autoMatch);
                  },
            child: state.busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onGold))
                : Text.rich(TextSpan(children: [
                    const TextSpan(text: "I'm ready"),
                    if (stake != null) TextSpan(text: '  ${MoneyFormatter.compactEtb(stake.stakeAmountMinor)}', style: AppType.money(size: 18)),
                  ])),
          );

    if (folded) {
      final variant = typed ? GameVariants.find(state.myRules) : null;
      return Row(children: [
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (variant != null) VariantTag(variant: variant),
            if (isLudo) GoalCrowns(goal: prefs.tokensToWin),
            if (prefs.autoMatch) Icon(Icons.bolt_rounded, size: 16, color: theme.colorScheme.primary, semanticLabel: 'Auto-match on'),
          ]),
        ),
        const SizedBox(width: 10),
        action,
      ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (typed) ...[
        VariantPicker(
          compact: true,
          variants: state.offeredVariants,
          selected: GameVariants.find(state.myRules),
          readyCounts: {for (final variant in state.offeredVariants) variant: state.readyCountOfRules(variant.rulesVersion)},
          enabled: !locked,
          onChanged: (variant) => controller.switchRules(variant.rulesVersion),
        ),
        const SizedBox(height: 10),
      ],
      if (isLudo) ...[
        GoalChips(selected: prefs.tokensToWin, enabled: !locked, onChanged: preferences.setTokensToWin),
        const SizedBox(height: 10),
      ],
      _StakeGrid(
        stakes: stakes,
        selectedId: state.myStakeId,
        enabled: !locked,
        canCover: canCover,
        readyAt: state.readyCountAt,
        onPick: controller.changeStake,
        onOther: onOtherAmount,
      ),
      const SizedBox(height: 6),
      _AutoMatchSwitch(value: prefs.autoMatch, enabled: !locked, onChanged: preferences.setAutoMatch),
      const SizedBox(height: 6),
      action,
      if (stake != null) ...[
        const SizedBox(height: 8),
        DefaultTextStyle.merge(
          style: theme.textTheme.bodySmall,
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Winner gets '),
                  TextSpan(text: MoneyFormatter.compactEtb(stake.estimatedWinnerPayoutMinor), style: AppType.money(size: 15, color: palette.money)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('${stake.turnDurationSeconds}s per move'),
          ]),
        ),
      ],
    ]);
  }
}

/// "Auto-match": start with the next player ready at the same terms.
class _AutoMatchSwitch extends StatelessWidget {
  const _AutoMatchSwitch({required this.value, required this.enabled, required this.onChanged});
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(Icons.bolt_rounded, size: 20, color: value ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Auto-match', style: theme.textTheme.titleSmall),
                Text('Start with the next player ready at the same terms', maxLines: 2, style: theme.textTheme.bodySmall),
              ]),
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null),
          ]),
        ),
      ),
    );
  }
}

/// Ready: what I asked for, that I'm waiting (a match starts by itself with
/// auto-match), and Edit.
class _WaitingBar extends ConsumerWidget {
  const _WaitingBar({required this.state, this.folded = false});
  final LiveLobbyState state;

  /// Just the status line (no terms, no Edit).
  final bool folded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final controller = ref.read(liveLobbyControllerProvider.notifier);
    final me = state.selfPlayer;
    final stake = state.myStake;
    // What the server holds for me (my row), else what I chose on this device.
    final prefs = ref.watch(playerPreferencesProvider);
    final bool autoMatch = me?.autoMatch ?? prefs.autoMatch;
    final int? goal = state.gameCode == GameCodes.ludo ? (me?.tokensToWin ?? prefs.tokensToWin) : null;
    final variant = _typeOf(state, stake);
    final title = state.isChallenged
        ? 'A request is open…'
        : autoMatch
            ? 'Looking for a player…'
            : 'Waiting for someone to play you';
    return Semantics(
      container: true,
      liveRegion: true,
      label: "You're ready. $title",
      child: Row(children: [
        const TokenHopLoader(cell: 10),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: palette.live)),
            if (!folded) const SizedBox(height: 4),
            if (!folded)
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (variant != null) VariantTag(variant: variant),
                if (goal != null) GoalCrowns(goal: goal),
                if (stake != null) Text(MoneyFormatter.compactEtb(stake.stakeAmountMinor), style: AppType.money(size: 16, color: palette.money)),
                if (autoMatch) Icon(Icons.bolt_rounded, size: 16, color: theme.colorScheme.primary, semanticLabel: 'Auto-match on'),
              ]),
          ]),
        ),
        if (!folded) const SizedBox(width: 10),
        if (!folded)
          OutlinedButton.icon(
            onPressed: state.busy || state.isChallenged ? null : controller.unready,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
      ]),
    );
  }
}

/// Stakes as chips in a grid, then "Other amount". The chosen one is gold.
class _StakeGrid extends StatelessWidget {
  const _StakeGrid({
    required this.stakes,
    required this.selectedId,
    required this.enabled,
    required this.canCover,
    required this.readyAt,
    required this.onPick,
    required this.onOther,
  });

  final List<GameMode> stakes;
  final String? selectedId;
  final bool enabled;
  final bool Function(GameMode stake) canCover;
  final int Function(String stakeId) readyAt;
  final ValueChanged<String> onPick;
  final VoidCallback onOther;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 8.0;
      final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns = (constraints.maxWidth / (68 * textScale)).floor().clamp(3, 6);
      final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
      final otherSpan = columns >= 4 ? 2 : columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final stake in stakes)
          Builder(builder: (context) {
            final selected = stake.id == selectedId;
            final covered = canCover(stake);
            final ready = readyAt(stake.id);
            final amount = _chipAmount(stake.stakeAmountMinor);
            return SizedBox(
              width: cell,
              child: Semantics(
                button: true,
                selected: selected,
                enabled: enabled && covered,
                label: '${MoneyFormatter.compactEtb(stake.stakeAmountMinor)}${ready > 0 ? ', $ready ready' : ''}'
                    '${covered ? '' : ', add funds to play'}',
                excludeSemantics: true,
                child: Material(
                  color: selected ? palette.selected : palette.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: selected ? AppColors.gold : palette.border, width: selected ? 1.5 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: enabled && covered && !selected
                        ? () {
                            HapticFeedback.selectionClick();
                            onPick(stake.id);
                          }
                        : null,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 46),
                      alignment: Alignment.center,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Text(
                          amount,
                          maxLines: 1,
                          style: AppType.money(
                            size: 19,
                            color: selected
                                ? scheme.primary
                                : covered
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        if (ready > 0) Positioned(right: -9, top: -2, child: LiveDot(size: 6, color: palette.live)),
                      ]),
                    ),
                  ),
                ),
              ),
            );
          }),
        SizedBox(
          width: cell * otherSpan + gap * (otherSpan - 1),
          child: Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: palette.border)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? onOther : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 46),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit_outlined, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Other amount',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.ui(size: 14.5, weight: FontWeight.w600, color: scheme.onSurface),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  /// 50, 100, 1K, 2.5K, 10K: whole birr, short on a chip (ETB is implied).
  static String _chipAmount(int amountMinor) {
    final etb = amountMinor / 100;
    if (etb >= 1000) {
      final k = etb / 1000;
      return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)}K';
    }
    return etb == etb.roundToDouble() ? etb.toStringAsFixed(0) : etb.toStringAsFixed(2);
  }
}

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
          if (_typeOf(state, stake) case final type?) ...[VariantTag(variant: type, emphasized: true), const SizedBox(width: 8)],
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

/// Playing someone on their terms when they differ from mine: their stake
/// (and type) and, in Ludo, their goal ([theirGoal] when it differs).
Future<bool?> _confirmStakeChange(
  BuildContext context,
  LobbyPlayer player,
  GameMode stake, {
  GameVariant? theirType,
  GameVariant? myType,
  int? theirGoal,
}) {
  final theme = Theme.of(context);
  // The type I switch to, when it differs from mine.
  final GameVariant? newType = theirType != null && theirType != myType ? theirType : null;
  final what = [
    if (newType != null) 'game type',
    'stake',
    if (theirGoal != null) 'goal',
  ];
  return showAppSheet<bool>(
    context,
    builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'Play ${player.displayName} for ${MoneyFormatter.compactEtb(stake.stakeAmountMinor)}?',
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        newType != null
            ? '${player.displayName} plays ${newType.name}: ${newType.rule.toLowerCase()} '
                'You play on their terms (${what.join(', ')}).'
            : 'You play on ${player.displayName}\'s terms (${what.join(', ')}).',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
      if (theirGoal != null) ...[
        Row(children: [
          GoalCrowns(goal: theirGoal, size: 16),
          const SizedBox(width: 8),
          Text(GoalChips.label(theirGoal), style: theme.textTheme.titleSmall),
        ]),
        const SizedBox(height: 10),
      ],
      if (newType != null) ...[
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (myType != null) ...[
            VariantTag(variant: myType, large: true),
            Icon(Icons.arrow_forward_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
          VariantTag(variant: newType, emphasized: true, large: true),
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
