import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/chat/domain/chat_message.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_player_dice_panel.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_player_strip.dart';

class LudoMatchScreen extends ConsumerStatefulWidget {
  const LudoMatchScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<LudoMatchScreen> createState() => _LudoMatchScreenState();
}

class _LudoMatchScreenState extends ConsumerState<LudoMatchScreen> with WidgetsBindingObserver {
  String? _pendingTokenId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(ludoMatchControllerProvider.notifier).join(widget.matchId));
    Future.microtask(() => ref.read(matchChatControllerProvider.notifier).load(widget.matchId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(ludoMatchControllerProvider.notifier).recover(reason: 'app_resume'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(ludoMatchControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final socket = ref.watch(gameSocketStatusProvider);
    final animation = ref.watch(ludoAnimationQueueProvider);
    final chat = ref.watch(matchChatControllerProvider);
    final snapshot = match.snapshot;

    // Clear local pending token when command settles.
    if (match.pendingCommandId == null && _pendingTokenId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(ludoMatchControllerProvider).pendingCommandId == null) {
          setState(() => _pendingTokenId = null);
        }
      });
    }

    if (match.loading || snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ludo')),
        body: Center(
          child: match.error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(match.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref.read(ludoMatchControllerProvider.notifier).join(widget.matchId),
                      child: const Text('Try again'),
                    ),
                  ]),
                ),
        ),
      );
    }

    final game = snapshot.game;
    final me = auth.user?.id;
    final actionsAllowed = match.pendingCommandId == null &&
        !match.recovering &&
        socket == GameSocketStatus.connected;
    final myTurn = me != null && game.currentPlayerId == me;
    final canStartRoll = game.phase == LudoMatchPhase.preGame &&
        game.turnPhase == LudoTurnPhase.startRoll &&
        me != null &&
        snapshot.startingRoll.candidatePlayerIds.contains(me) &&
        !snapshot.startingRoll.rolls.containsKey(me) &&
        actionsAllowed;
    final canRoll = game.phase == LudoMatchPhase.playing &&
        game.turnPhase == LudoTurnPhase.waitingForRoll &&
        myTurn &&
        actionsAllowed;

    final tokens = _buildTokens(
      game: game,
      me: me,
      actionsAllowed: actionsAllowed,
      animation: animation.current,
      pendingTokenId: _pendingTokenId,
    );

    final ordered = _orderedParticipants(match.participants, snapshot, me);
    final mine = ordered.isNotEmpty ? ordered.first : null;
    final opponent = ordered.length > 1 ? ordered[1] : null;

    final dicePair = mine != null && opponent != null
        ? _resolveDicePair(
            snapshot: snapshot,
            mine: mine,
            opponent: opponent,
            lastDiceByPlayer: match.lastDiceByPlayer,
            animation: animation.current,
            animationSequence: animation.sequence,
          )
        : null;

    final scheme = Theme.of(context).colorScheme;
    final preGame = game.phase == LudoMatchPhase.preGame;
    final opponentActive = opponent != null && game.currentPlayerId == opponent.userId && !preGame;
    final meActive = mine != null && game.currentPlayerId == mine.userId && !preGame;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _ConnectionBanner(status: socket, recovering: match.recovering),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: opponent != null
                  ? LudoPlayerStrip(
                      participant: opponent,
                      myUserId: me,
                      isActive: opponentActive || (preGame && snapshot.startingRoll.candidatePlayerIds.contains(opponent.userId)),
                      turnEndsAt: opponentActive ? match.timing?.turnEndsAt : null,
                      timingEstimated: match.timing?.estimated == true,
                      startingRoll: preGame ? snapshot.startingRoll.rolls[opponent.userId] : null,
                      statusOverride: preGame
                          ? (snapshot.startingRoll.rolls.containsKey(opponent.userId) ? 'Rolled' : 'Rolling…')
                          : null,
                    )
                  : const SizedBox(height: 48),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.maxWidth < constraints.maxHeight
                      ? constraints.maxWidth
                      : constraints.maxHeight;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: LudoBoard(
                          tokens: tokens,
                          animatedMove:
                              animation.current?.kind == LudoPresentationKind.move ? animation.current?.move : null,
                          animationSequence: animation.sequence,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: mine != null
                  ? LudoPlayerStrip(
                      participant: mine,
                      myUserId: me,
                      isActive: meActive || canStartRoll,
                      turnEndsAt: meActive ? match.timing?.turnEndsAt : null,
                      timingEstimated: match.timing?.estimated == true,
                      startingRoll: preGame ? snapshot.startingRoll.rolls[mine.userId] : null,
                      showYouLabel: true,
                      statusOverride: preGame
                          ? (canStartRoll
                              ? 'Tap dice to roll'
                              : snapshot.startingRoll.rolls.containsKey(mine.userId)
                                  ? 'Rolled'
                                  : 'Waiting')
                          : null,
                    )
                  : const SizedBox(height: 48),
            ),
            if (match.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _InlineMessage(message: match.error!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dicePair != null)
                    LudoPlayerDicePanel(
                      myParticipant: dicePair.mine,
                      opponentParticipant: dicePair.opponent,
                      myDiceValue: dicePair.myDiceValue,
                      opponentDiceValue: dicePair.opponentDiceValue,
                      myAnimateKey: dicePair.myAnimateKey,
                      opponentAnimateKey: dicePair.opponentAnimateKey,
                      myDiceState: _diceState(
                        canRoll: canStartRoll || canRoll,
                        busy: match.pendingCommandId != null || match.recovering,
                        hasValue: dicePair.myDiceValue != null,
                        rolling: animation.current?.kind == LudoPresentationKind.dice &&
                            animation.current?.playerId == dicePair.mine.userId,
                      ),
                      opponentDiceState: _diceState(
                        canRoll: false,
                        busy: false,
                        hasValue: dicePair.opponentDiceValue != null,
                        rolling: animation.current?.kind == LudoPresentationKind.dice &&
                            animation.current?.playerId == dicePair.opponent.userId,
                      ),
                      onRollMine: canStartRoll
                          ? () => ref.read(ludoMatchControllerProvider.notifier).rollForStart()
                          : () => ref.read(ludoMatchControllerProvider.notifier).roll(),
                      preGame: preGame,
                      headline: _headline(game, me, match.participants, canStartRoll, canRoll),
                      detail: _detail(game, me, snapshot),
                    )
                  else
                    Text('Waiting for players…', style: Theme.of(context).textTheme.bodyMedium),
                  if (match.pendingCommandId != null) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  if (game.phase == LudoMatchPhase.finished) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => context.pushReplacement('/ludo/result/${widget.matchId}'),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('View result & settlement'),
                    ),
                  ],
                  const SizedBox(height: 6),
                  _BottomBar(
                    unread: chat.unread,
                    sessionCode: match.sessionCode,
                    recovering: match.recovering,
                    onChat: () => _openChat(context),
                    onMenu: () => _openMenu(context, match),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<LudoBoardTokenView> _buildTokens({
    required LudoGameState game,
    required String? me,
    required bool actionsAllowed,
    required LudoPresentationEvent? animation,
    required String? pendingTokenId,
  }) {
    final raw = <({LudoToken token, int baseIndex})>[];
    for (final player in game.players) {
      for (var i = 0; i < player.tokens.length; i++) {
        raw.add((token: player.tokens[i], baseIndex: i));
      }
    }

    final groups = <String, List<int>>{};
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      final key = LudoBoardGeometry.occupancyKey(
        color: item.token.color,
        progress: item.token.progress,
        tokenId: item.token.id,
      );
      groups.putIfAbsent(key, () => []).add(i);
    }

    final stackIndexByToken = <String, int>{};
    final stackCountByToken = <String, int>{};
    for (final entry in groups.entries) {
      final indexes = entry.value;
      final count = indexes.length;
      for (var s = 0; s < indexes.length; s++) {
        final tokenId = raw[indexes[s]].token.id;
        stackIndexByToken[tokenId] = s;
        stackCountByToken[tokenId] = count;
      }
    }

    return [
      for (final item in raw)
        LudoBoardTokenView(
          id: item.token.id,
          color: item.token.color,
          progress: item.token.progress,
          baseIndex: item.baseIndex,
          highlighted: me == item.token.ownerId &&
              game.legalTokenIds.contains(item.token.id) &&
              actionsAllowed &&
              pendingTokenId == null,
          emphasized: animation?.kind == LudoPresentationKind.capture &&
              (animation?.tokenIds.contains(item.token.id) ?? false),
          pending: pendingTokenId == item.token.id,
          finished: item.token.state == LudoTokenState.finished || item.token.progress > 56,
          stackIndex: stackIndexByToken[item.token.id] ?? 0,
          stackCount: stackCountByToken[item.token.id] ?? 1,
          onTap: me == item.token.ownerId &&
                  game.legalTokenIds.contains(item.token.id) &&
                  actionsAllowed &&
                  pendingTokenId == null
              ? () {
                  setState(() => _pendingTokenId = item.token.id);
                  ref.read(ludoMatchControllerProvider.notifier).move(item.token.id);
                }
              : null,
        ),
    ];
  }

  LudoDiceVisualState _diceState({
    required bool canRoll,
    required bool busy,
    required bool hasValue,
    required bool rolling,
  }) {
    if (rolling) return LudoDiceVisualState.rolling;
    if (canRoll && !busy) return LudoDiceVisualState.ready;
    if (busy) return LudoDiceVisualState.disabled;
    if (hasValue) return LudoDiceVisualState.result;
    return LudoDiceVisualState.waiting;
  }

  String _headline(
    LudoGameState game,
    String? me,
    List<LudoMatchParticipant> participants,
    bool canStartRoll,
    bool canRoll,
  ) {
    if (game.phase == LudoMatchPhase.finished) return 'Match finished';
    if (game.phase == LudoMatchPhase.preGame) {
      if (canStartRoll) return 'Roll to decide who starts';
      return 'Waiting for starting rolls';
    }
    if (game.turnPhase == LudoTurnPhase.waitingForMove) {
      return game.currentPlayerId == me ? 'Choose a token' : '${_playerName(game.currentPlayerId, me, participants)} is choosing';
    }
    if (canRoll) return 'Your turn — roll';
    return game.currentPlayerId == me ? 'Roll when ready' : '${_playerName(game.currentPlayerId, me, participants)} is playing';
  }

  String _detail(LudoGameState game, String? me, LudoRuntimeSnapshot snapshot) {
    if (game.phase == LudoMatchPhase.finished) {
      final won = game.winnerOrder.isNotEmpty && game.winnerOrder.first == me;
      return won ? 'You won. Settlement is handled by the server.' : 'Result confirmed by the server.';
    }
    if (game.phase == LudoMatchPhase.preGame) {
      final rolls = snapshot.startingRoll.rolls;
      if (rolls.length >= 2) {
        final values = rolls.values.toList();
        if (values[0] == values[1]) return 'Tie — roll again';
      }
      return 'Highest roll starts the match.';
    }
    if (game.turnPhase == LudoTurnPhase.waitingForMove && game.currentPlayerId == me) {
      return '${game.legalTokenIds.length} legal move${game.legalTokenIds.length == 1 ? '' : 's'}';
    }
    return '';
  }

  String _playerName(String? userId, String? me, List<LudoMatchParticipant> participants) {
    if (userId == null) return 'Opponent';
    if (userId == me) return 'You';
    for (final participant in participants) {
      if (participant.userId == userId) return participant.displayLabel(myUserId: me);
    }
    return 'Opponent';
  }

  Future<void> _confirmResign(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign match?'),
        content: const Text('Resigning ends your participation and may settle the match for your opponent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Resign')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(ludoMatchControllerProvider.notifier).resign();
  }

  Future<void> _openChat(BuildContext context) async {
    final controller = ref.read(matchChatControllerProvider.notifier);
    controller.setPanelOpen(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _MatchChatSheet(),
    );
    controller.setPanelOpen(false);
  }

  Future<void> _openMenu(BuildContext context, LudoMatchViewState match) async {
    final game = match.snapshot?.game;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (match.sessionCode != null && match.sessionCode!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.tag_rounded),
                  title: Text('Game ${match.sessionCode}'),
                  subtitle: const Text('Session code'),
                ),
              ListTile(
                leading: match.recovering
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_rounded),
                title: const Text('Sync game'),
                onTap: match.recovering
                    ? null
                    : () {
                        Navigator.pop(context);
                        ref.read(ludoMatchControllerProvider.notifier).recover(reason: 'manual_refresh');
                      },
              ),
              if (game?.phase != LudoMatchPhase.finished)
                ListTile(
                  leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
                  title: Text('Resign', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmResign(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Close'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.unread,
    required this.sessionCode,
    required this.recovering,
    required this.onChat,
    required this.onMenu,
  });

  final int unread;
  final String? sessionCode;
  final bool recovering;
  final VoidCallback onChat;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Match chat',
          onPressed: onChat,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread.toString()),
            child: const Icon(Icons.chat_bubble_outline),
          ),
        ),
        if (sessionCode != null && sessionCode!.isNotEmpty)
          Expanded(
            child: Text(
              'Game $sessionCode',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        else
          const Spacer(),
        IconButton(
          tooltip: 'Menu',
          onPressed: onMenu,
          icon: recovering
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.more_horiz_rounded),
        ),
      ],
    );
  }
}

class _MatchChatSheet extends ConsumerStatefulWidget {
  const _MatchChatSheet();

  @override
  ConsumerState<_MatchChatSheet> createState() => _MatchChatSheetState();
}

class _MatchChatSheetState extends ConsumerState<_MatchChatSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(matchChatControllerProvider);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text('Match Chat', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            if (chat.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(chat.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: chat.loading
                  ? const Center(child: CircularProgressIndicator())
                  : chat.messages.isEmpty
                      ? const Center(child: Text('No match messages yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: chat.messages.length,
                          itemBuilder: (context, index) => _ChatLine(message: chat.messages[index]),
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLength: 160,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(hintText: 'Message...', counterText: ''),
                        onSubmitted: (_) => _send(chat.sending),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: chat.sending ? null : () => _send(false),
                      icon: chat.sending
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
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

  void _send(bool sending) {
    if (sending) return;
    final text = _controller.text;
    _controller.clear();
    ref.read(matchChatControllerProvider.notifier).send(text);
  }
}

class _ChatLine extends StatelessWidget {
  const _ChatLine({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(message.sender.displayName, style: Theme.of(context).textTheme.labelLarge),
        subtitle: Text(message.text),
        trailing: Text(_time(message.createdAt), style: Theme.of(context).textTheme.labelSmall),
      );

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _PlayerDicePair {
  const _PlayerDicePair({
    required this.mine,
    required this.opponent,
    required this.myDiceValue,
    required this.opponentDiceValue,
    required this.myAnimateKey,
    required this.opponentAnimateKey,
  });

  final LudoMatchParticipant mine;
  final LudoMatchParticipant opponent;
  final int? myDiceValue;
  final int? opponentDiceValue;
  final int myAnimateKey;
  final int opponentAnimateKey;
}

_PlayerDicePair _resolveDicePair({
  required LudoRuntimeSnapshot snapshot,
  required LudoMatchParticipant mine,
  required LudoMatchParticipant opponent,
  required Map<String, int> lastDiceByPlayer,
  required LudoPresentationEvent? animation,
  required int animationSequence,
}) {
  int? diceFor(String userId) {
    if (animation?.kind == LudoPresentationKind.dice && animation?.playerId == userId) {
      return animation?.diceValue;
    }
    final game = snapshot.game;
    if (game.diceValue != null && game.currentPlayerId == userId) return game.diceValue;
    if (game.phase == LudoMatchPhase.preGame) return snapshot.startingRoll.rolls[userId];
    return lastDiceByPlayer[userId];
  }

  int animateKeyFor(String userId) =>
      animation?.kind == LudoPresentationKind.dice && animation?.playerId == userId ? animationSequence : 0;

  return _PlayerDicePair(
    mine: mine,
    opponent: opponent,
    myDiceValue: diceFor(mine.userId),
    opponentDiceValue: diceFor(opponent.userId),
    myAnimateKey: animateKeyFor(mine.userId),
    opponentAnimateKey: animateKeyFor(opponent.userId),
  );
}

List<LudoMatchParticipant> _orderedParticipants(
  List<LudoMatchParticipant> participants,
  LudoRuntimeSnapshot snapshot,
  String? myUserId,
) {
  final source = participants.isNotEmpty
      ? participants
      : snapshot.game.players
          .map((player) => LudoMatchParticipant(userId: player.userId, fullName: 'Player', seat: 0, color: player.color))
          .toList(growable: false);

  if (myUserId == null || source.length < 2) return source;

  final mine = source.where((p) => p.userId == myUserId).toList();
  final others = source.where((p) => p.userId != myUserId).toList();
  if (mine.isEmpty || others.isEmpty) return source;
  return [mine.first, others.first];
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.status, required this.recovering});
  final GameSocketStatus status;
  final bool recovering;

  @override
  Widget build(BuildContext context) {
    if (status == GameSocketStatus.connected && !recovering) return const SizedBox.shrink();
    final text = recovering
        ? 'Recovering match…'
        : status == GameSocketStatus.connecting || status == GameSocketStatus.recovering
            ? 'Reconnecting…'
            : 'Connection lost — board preserved';
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13)),
      );
}
