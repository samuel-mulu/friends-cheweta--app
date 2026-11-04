import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/chat/domain/chat_message.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_feedback.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';

/// In-match screen. Layout works for 2, 3 or 4 players: the board is rotated
/// so the viewer's color sits bottom-left, and every player has a corner seat
/// (avatar, turn ring, own dice). All game outcomes come from the server; the
/// screen only presents them, in order, via the animation queue.
class LudoMatchScreen extends ConsumerStatefulWidget {
  const LudoMatchScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<LudoMatchScreen> createState() => _LudoMatchScreenState();
}

class _LudoMatchScreenState extends ConsumerState<LudoMatchScreen> with WidgetsBindingObserver {
  String? _pendingTokenId;

  /// Per-player dice presentation counters: only ever increase, so a die
  /// animates for its own owner's rolls and nothing else.
  final Map<String, int> _diceKeys = {};

  /// Last face *presented* per player (the controller may already know a
  /// newer one that is still queued; showing it early would spoil the roll).
  final Map<String, int> _presentedDice = {};

  /// My die spins from the tap until my roll is presented (or rejected).
  bool _mySpin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(gameSoundServiceProvider).preload();
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

  void _onPresentation(LudoAnimationState? previous, LudoAnimationState next) {
    final event = next.current;
    if (event == null || next.sequence == previous?.sequence) return;
    final me = ref.read(authControllerProvider).user?.id;
    final snapshot = ref.read(ludoMatchControllerProvider).snapshot;

    if (event.kind == LudoPresentationKind.dice && event.playerId != null) {
      setState(() {
        _diceKeys[event.playerId!] = next.sequence;
        if (event.diceValue != null) _presentedDice[event.playerId!] = event.diceValue!;
        if (event.playerId == me) _mySpin = false;
      });
    }

    final feedback = feedbackFor(
      event,
      me: me,
      winnerOrder: snapshot?.game.winnerOrder ?? const [],
      tokenOwners: {
        for (final player in snapshot?.game.players ?? const <LudoPlayerState>[])
          for (final token in player.tokens) token.id: token.ownerId,
      },
    );
    if (feedback.sound != null) ref.read(gameSoundServiceProvider).play(feedback.sound!, volume: feedback.volume);
    switch (feedback.haptic) {
      case LudoHaptic.light:
        HapticFeedback.lightImpact();
      case LudoHaptic.medium:
        HapticFeedback.mediumImpact();
      case LudoHaptic.heavy:
        HapticFeedback.heavyImpact();
      case null:
        break;
    }
  }

  Future<void> _rollMine({required bool startRoll}) async {
    HapticFeedback.selectionClick();
    setState(() => _mySpin = true);
    final controller = ref.read(ludoMatchControllerProvider.notifier);
    final ok = startRoll ? await controller.rollForStart() : await controller.roll();
    if (!ok && mounted) setState(() => _mySpin = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ludoAnimationQueueProvider, _onPresentation);
    final match = ref.watch(ludoMatchControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    final socket = ref.watch(gameSocketStatusProvider);
    final animation = ref.watch(ludoAnimationQueueProvider);
    final chat = ref.watch(matchChatControllerProvider);
    final soundOn = ref.watch(gameSoundEnabledProvider);
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
    final participants = _participants(match.participants, snapshot);
    final myColor = participants.where((p) => p.userId == me).firstOrNull?.color;
    final orientation = LudoBoardOrientation.forViewer(myColor);
    final actionsAllowed = match.pendingCommandId == null && !match.recovering && socket == GameSocketStatus.connected;
    final presenting = animation.busy;
    final seats = [
      for (final participant in participants)
        _seatFor(
          participant: participant,
          snapshot: snapshot,
          match: match,
          me: me,
          orientation: orientation,
          actionsAllowed: actionsAllowed,
          animation: animation,
        ),
    ];
    LudoSeatView? seatAt(LudoCorner corner) => seats.where((seat) => seat.corner == corner).firstOrNull;

    final tokens = _buildTokens(
      game: game,
      me: me,
      // Wait for the queue to finish presenting before inviting a move, so a
      // highlighted token never appears before its dice has landed.
      actionsAllowed: actionsAllowed && !presenting,
      animation: animation.current,
      pendingTokenId: _pendingTokenId,
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ConnectionBanner(status: socket, recovering: match.recovering),
            _TopBar(
              unread: chat.unread,
              sessionCode: match.sessionCode,
              soundOn: soundOn,
              recovering: match.recovering,
              onChat: () => _openChat(context),
              onToggleSound: () => ref.read(gameSoundEnabledProvider.notifier).toggle(),
              onMenu: () => _openMenu(context, match),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    _SeatRow(left: seatAt(LudoCorner.topLeft), right: seatAt(LudoCorner.topRight)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Center(
                        child: LudoBoard(
                          tokens: tokens,
                          orientation: orientation,
                          animatedMove: animation.current?.kind == LudoPresentationKind.move ? animation.current?.move : null,
                          animationSequence: animation.sequence,
                          onStep: () => ref.read(gameSoundServiceProvider).play(GameSound.step, volume: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SeatRow(
                      left: seatAt(LudoCorner.bottomLeft),
                      right: seatAt(LudoCorner.bottomRight),
                      onWarningSecond: () => ref.read(gameSoundServiceProvider).play(GameSound.tick, volume: 0.6),
                      warnUserId: me,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (match.error != null) _InlineMessage(message: match.error!),
                _Headline(text: _headline(game, snapshot, me, participants)),
                if (game.phase == LudoMatchPhase.finished && !presenting) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => context.pushReplacement('/ludo/result/${widget.matchId}'),
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: const Text('View result'),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  LudoSeatView _seatFor({
    required LudoMatchParticipant participant,
    required LudoRuntimeSnapshot snapshot,
    required LudoMatchViewState match,
    required String? me,
    required LudoBoardOrientation orientation,
    required bool actionsAllowed,
    required LudoAnimationState animation,
  }) {
    final game = snapshot.game;
    final userId = participant.userId;
    final isMe = userId == me;
    final preGame = game.phase == LudoMatchPhase.preGame;
    final startRolled = snapshot.startingRoll.rolls.containsKey(userId);
    final startCandidate = snapshot.startingRoll.candidatePlayerIds.contains(userId);
    final active = preGame ? startCandidate && !startRolled : game.currentPlayerId == userId && game.phase == LudoMatchPhase.playing;
    final resigned = snapshot.resignedPlayerIds.contains(userId);
    final rankIndex = game.winnerOrder.indexOf(userId);

    final canStartRoll = isMe && preGame && game.turnPhase == LudoTurnPhase.startRoll && startCandidate && !startRolled;
    final canRoll = isMe && !preGame && active && game.turnPhase == LudoTurnPhase.waitingForRoll;
    final rollingNow = animation.current?.kind == LudoPresentationKind.dice && animation.current?.playerId == userId;

    final diceState = rollingNow
        ? LudoDiceVisualState.rolling
        : (canStartRoll || canRoll) && actionsAllowed && !animation.busy
            ? LudoDiceVisualState.ready
            : active
                ? LudoDiceVisualState.waiting
                : LudoDiceVisualState.disabled;

    final status = resigned
        ? 'Left'
        : rankIndex >= 0
            ? (rankIndex == 0 ? 'Winner' : 'Finished')
            : preGame
                ? (startRolled ? 'Rolled' : (startCandidate ? (isMe ? 'Tap to roll' : 'Rolling…') : null))
                : active
                    ? (game.turnPhase == LudoTurnPhase.waitingForMove
                        ? (isMe ? 'Move a token' : 'Moving…')
                        : (isMe ? 'Your turn' : 'Rolling…'))
                    : null;

    return LudoSeatView(
      participant: participant,
      corner: orientation.cornerOf(participant.color ?? LudoColor.red),
      isMe: isMe,
      active: active,
      diceValue: _presentedDice[userId] ?? (preGame ? snapshot.startingRoll.rolls[userId] : null),
      diceKey: _diceKeys[userId] ?? 0,
      spinning: isMe && _mySpin,
      diceState: diceState,
      turnEndsAt: active ? match.timing?.turnEndsAt : null,
      turnSeconds: match.turnDurationSeconds,
      status: status,
      rank: rankIndex >= 0 && game.players.length > 2 ? rankIndex + 1 : (rankIndex == 0 ? 1 : null),
      resigned: resigned,
      onRoll: canStartRoll || canRoll ? () => _rollMine(startRoll: canStartRoll) : null,
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
      final key = LudoBoardGeometry.occupancyKey(color: item.token.color, progress: item.token.progress, tokenId: item.token.id);
      groups.putIfAbsent(key, () => []).add(i);
    }
    final stackIndexByToken = <String, int>{};
    final stackCountByToken = <String, int>{};
    for (final indexes in groups.values) {
      for (var s = 0; s < indexes.length; s++) {
        final tokenId = raw[indexes[s]].token.id;
        stackIndexByToken[tokenId] = s;
        stackCountByToken[tokenId] = indexes.length;
      }
    }

    return [
      for (final item in raw)
        () {
          final selectable = me == item.token.ownerId &&
              game.legalTokenIds.contains(item.token.id) &&
              actionsAllowed &&
              pendingTokenId == null;
          return LudoBoardTokenView(
            id: item.token.id,
            color: item.token.color,
            progress: item.token.progress,
            baseIndex: item.baseIndex,
            highlighted: selectable,
            emphasized: animation?.kind == LudoPresentationKind.capture && (animation?.tokenIds.contains(item.token.id) ?? false),
            pending: pendingTokenId == item.token.id,
            finished: item.token.state == LudoTokenState.finished || item.token.progress > 56,
            stackIndex: stackIndexByToken[item.token.id] ?? 0,
            stackCount: stackCountByToken[item.token.id] ?? 1,
            onTap: selectable
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() => _pendingTokenId = item.token.id);
                    ref.read(ludoMatchControllerProvider.notifier).move(item.token.id);
                  }
                : null,
          );
        }(),
    ];
  }

  String _headline(LudoGameState game, LudoRuntimeSnapshot snapshot, String? me, List<LudoMatchParticipant> participants) {
    String name(String? id) {
      if (id == me) return 'You';
      return participants.where((p) => p.userId == id).firstOrNull?.displayLabel() ?? 'Opponent';
    }

    if (game.phase == LudoMatchPhase.finished) {
      return game.winnerOrder.isNotEmpty && game.winnerOrder.first == me ? 'You won!' : '${name(game.winnerOrder.firstOrNull)} won';
    }
    if (game.phase == LudoMatchPhase.preGame) {
      final mine = me != null && snapshot.startingRoll.candidatePlayerIds.contains(me) && !snapshot.startingRoll.rolls.containsKey(me);
      if (snapshot.startingRoll.round > 1) return mine ? 'Tie! Roll again' : 'Tie, rolling again…';
      return mine ? 'Roll to decide who starts' : 'Highest roll starts';
    }
    final current = game.currentPlayerId;
    if (current == me) {
      return game.turnPhase == LudoTurnPhase.waitingForMove ? 'Choose a token to move' : 'Your turn: tap your dice';
    }
    return '${name(current)} ${game.turnPhase == LudoTurnPhase.waitingForMove ? 'is moving' : 'is rolling'}';
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (match.sessionCode != null && match.sessionCode!.isNotEmpty)
              ListTile(leading: const Icon(Icons.tag_rounded), title: Text('Game ${match.sessionCode}'), subtitle: const Text('Session code')),
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
            ListTile(leading: const Icon(Icons.close_rounded), title: const Text('Close'), onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

/// Participants with colors filled from the game state (any player count).
List<LudoMatchParticipant> _participants(List<LudoMatchParticipant> participants, LudoRuntimeSnapshot snapshot) {
  final colorById = {for (final player in snapshot.game.players) player.userId: player.color};
  if (participants.isEmpty) {
    return [
      for (final (index, player) in snapshot.game.players.indexed)
        LudoMatchParticipant(userId: player.userId, fullName: 'Player', seat: index, color: player.color),
    ];
  }
  return [
    for (final p in participants)
      LudoMatchParticipant(userId: p.userId, fullName: p.fullName, seat: p.seat, color: p.color ?? colorById[p.userId]),
  ];
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({this.left, this.right, this.onWarningSecond, this.warnUserId});
  final LudoSeatView? left;
  final LudoSeatView? right;
  final VoidCallback? onWarningSecond;
  final String? warnUserId;

  @override
  Widget build(BuildContext context) {
    Widget seat(LudoSeatView? view) => view == null
        ? const SizedBox(width: 1, height: 1)
        : LudoSeat(seat: view, onWarningSecond: view.participant.userId == warnUserId ? onWarningSecond : null);
    return SizedBox(
      height: 104,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [seat(left), const Spacer(), seat(right)],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Text(
          text,
          key: ValueKey(text),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.unread,
    required this.sessionCode,
    required this.soundOn,
    required this.recovering,
    required this.onChat,
    required this.onToggleSound,
    required this.onMenu,
  });

  final int unread;
  final String? sessionCode;
  final bool soundOn;
  final bool recovering;
  final VoidCallback onChat;
  final VoidCallback onToggleSound;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          IconButton(
            tooltip: 'Match chat',
            onPressed: onChat,
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_outline)),
          ),
          Expanded(
            child: Text(
              sessionCode == null || sessionCode!.isEmpty ? '' : 'Game $sessionCode',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          IconButton(
            tooltip: soundOn ? 'Mute sounds' : 'Unmute sounds',
            onPressed: onToggleSound,
            icon: Icon(soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded),
          ),
          IconButton(
            tooltip: 'Menu',
            onPressed: onMenu,
            icon: recovering
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.more_horiz_rounded),
          ),
        ]),
      );
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
              child: Row(children: [
                Expanded(child: Text('Match Chat', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
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
                child: Row(children: [
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
                ]),
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onSecondaryContainer)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer))),
        ]),
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
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(10)),
        child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13)),
      );
}
