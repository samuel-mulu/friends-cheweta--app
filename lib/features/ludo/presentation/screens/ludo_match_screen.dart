import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_theme.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/chat_thread.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_feedback.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

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

  /// Presented rolls per player, newest first (shown as small faces).
  final Map<String, List<int>> _rollHistory = {};

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
        if (event.diceValue != null) {
          _presentedDice[event.playerId!] = event.diceValue!;
          _rollHistory[event.playerId!] = [event.diceValue!, ...?_rollHistory[event.playerId!]].take(3).toList();
        }
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
    if (!ref.read(playerPreferencesProvider).hapticsEnabled) return;
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

  void _tick() {
    if (ref.read(playerPreferencesProvider).hapticsEnabled) HapticFeedback.selectionClick();
  }

  void _moveToken(String tokenId) {
    _tick();
    setState(() => _pendingTokenId = tokenId);
    ref.read(ludoMatchControllerProvider.notifier).move(tokenId);
  }

  Future<void> _rollMine({required bool startRoll}) async {
    _tick();
    setState(() => _mySpin = true);
    final controller = ref.read(ludoMatchControllerProvider.notifier);
    final ok = startRoll ? await controller.rollForStart() : await controller.roll();
    if (!ok && mounted) setState(() => _mySpin = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ludoAnimationQueueProvider, _onPresentation);
    ref.listen(ludoMatchControllerProvider.select((s) => s.autoPlayNotice), (previous, next) {
      if (next == null || next.seq == previous?.seq) return;
      final me = ref.read(authControllerProvider).user?.id;
      final left = next.maxStrikes - next.strikes;
      final name = ref
              .read(ludoMatchControllerProvider)
              .participants
              .where((p) => p.userId == next.playerId)
              .firstOrNull
              ?.displayLabel() ??
          'Opponent';
      final text = next.playerId == me
          ? 'Time ran out, so we played for you (${next.strikes}/${next.maxStrikes}).'
              '${left > 0 ? ' $left more and you forfeit.' : ''}'
          : '$name is away, auto-played (${next.strikes}/${next.maxStrikes}).';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
    });
    final match = ref.watch(ludoMatchControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    final socket = ref.watch(gameSocketStatusProvider);
    final animation = ref.watch(ludoAnimationQueueProvider);
    final chat = ref.watch(matchChatControllerProvider);
    final prefs = ref.watch(playerPreferencesProvider);
    final soundOn = prefs.soundEnabled;
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

    final banner = _banner(game, snapshot, me, participants);
    final hint = _hint(game, me, presenting);

    // The match is always presented on the dark game table, regardless of the
    // app theme, like a dedicated game screen.
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1530),
        body: Stack(
          children: [
            const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _TableBackdrop()))),
            SafeArea(
              child: Column(
                children: [
                  _ConnectionBanner(status: socket, recovering: match.recovering),
                  _TopBar(
                    unread: chat.unread,
                    soundOn: soundOn,
                    recovering: match.recovering,
                    onExit: () => _confirmExit(context, game),
                    onChat: () => _openChat(context),
                    onToggleSound: () => ref.read(playerPreferencesProvider.notifier).setSound(!soundOn),
                    onMenu: () => _openMenu(context, match),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          _SeatRow(left: seatAt(LudoCorner.topLeft), right: seatAt(LudoCorner.topRight)),
                          const SizedBox(height: 6),
                          _TurnBanner(banner: banner),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: LudoBoard(
                                tokens: tokens,
                                orientation: orientation,
                                animatedMove:
                                    animation.current?.kind == LudoPresentationKind.move ? animation.current?.move : null,
                                animationSequence: animation.sequence,
                                onStep: () => ref.read(gameSoundServiceProvider).play(GameSound.step, volume: 0.5),
                                ghosts: _ghosts(match, game, me, myColor, actionsAllowed && !presenting),
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
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (match.error != null) _InlineMessage(message: match.error!),
                      SizedBox(
                        height: 20,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            hint,
                            key: ValueKey(hint),
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
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
      // Presented face first; after a reconnect fall back to the last known
      // roll, but never while a roll is queued (that would spoil it).
      diceValue: _presentedDice[userId] ??
          (animation.busy ? null : match.lastDiceByPlayer[userId]) ??
          (preGame ? snapshot.startingRoll.rolls[userId] : null),
      diceKey: _diceKeys[userId] ?? 0,
      spinning: isMe && _mySpin,
      diceState: diceState,
      turnEndsAt: active ? match.timing?.turnEndsAt : null,
      turnSeconds: match.turnDurationSeconds,
      status: status,
      rank: rankIndex >= 0 && game.players.length > 2 ? rankIndex + 1 : (rankIndex == 0 ? 1 : null),
      resigned: resigned,
      recentRolls: _rollHistory[userId] ?? const [],
      strikes: match.strikes[userId] ?? 0,
      maxStrikes: match.maxStrikes,
      onRoll: canStartRoll || canRoll ? () => _rollMine(startRoll: canStartRoll) : null,
    );
  }

  /// Landing previews while it is my move (the server computed them).
  List<LudoGhostView> _ghosts(LudoMatchViewState match, LudoGameState game, String? me, LudoColor? myColor, bool canAct) {
    if (!canAct ||
        myColor == null ||
        _pendingTokenId != null ||
        game.currentPlayerId != me ||
        game.turnPhase != LudoTurnPhase.waitingForMove) {
      return const [];
    }
    return [
      for (final preview in match.legalMoves)
        if (game.legalTokenIds.contains(preview.tokenId))
          LudoGhostView(
            tokenId: preview.tokenId,
            color: myColor,
            toProgress: preview.toProgress,
            captures: preview.captures.isNotEmpty,
            safe: preview.safe,
            onTap: () => _moveToken(preview.tokenId),
          ),
    ];
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
                ? () => _moveToken(item.token.id)
                : null,
          );
        }(),
    ];
  }

  _BannerData _banner(LudoGameState game, LudoRuntimeSnapshot snapshot, String? me, List<LudoMatchParticipant> participants) {
    LudoMatchParticipant? find(String? id) => participants.where((p) => p.userId == id).firstOrNull;
    String name(String? id) => (find(id)?.displayLabel() ?? 'Opponent').toUpperCase();
    const gold = Color(0xFFFFC83D);

    if (game.phase == LudoMatchPhase.finished) {
      final winner = game.winnerOrder.firstOrNull;
      return _BannerData(
        winner == me ? 'YOU WON!' : '${name(winner)} WON',
        find(winner)?.color?.color ?? gold,
        mine: winner == me,
      );
    }
    if (game.phase == LudoMatchPhase.preGame) {
      final mine = me != null && snapshot.startingRoll.candidatePlayerIds.contains(me) && !snapshot.startingRoll.rolls.containsKey(me);
      if (mine) return _BannerData(snapshot.startingRoll.round > 1 ? 'TIE! ROLL AGAIN' : 'ROLL TO START', find(me)?.color?.color ?? gold, mine: true);
      return const _BannerData('WHO STARTS?', gold);
    }
    final current = game.currentPlayerId;
    final color = find(current)?.color?.color ?? gold;
    return current == me ? _BannerData('YOUR TURN', color, mine: true) : _BannerData("${name(current)}'S TURN", color);
  }

  String _hint(LudoGameState game, String? me, bool presenting) {
    if (presenting || game.currentPlayerId != me || game.phase != LudoMatchPhase.playing) return '';
    return game.turnPhase == LudoTurnPhase.waitingForMove ? 'Tap a glowing token to move' : 'Tap your dice to roll';
  }

  Future<void> _confirmExit(BuildContext context, LudoGameState game) async {
    if (game.phase == LudoMatchPhase.finished) {
      context.pushReplacement('/ludo/result/${widget.matchId}');
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the match?'),
        content: const Text('Leaving now forfeits this match and your stake.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true || !context.mounted) return;
    final ok = await ref.read(ludoMatchControllerProvider.notifier).resign();
    if (ok && context.mounted) context.go('/home');
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
            Consumer(
              builder: (context, ref, _) => SwitchListTile(
                secondary: const Icon(Icons.speed_rounded),
                title: const Text('Fast animations'),
                value: ref.watch(playerPreferencesProvider.select((p) => p.fastAnimations)),
                onChanged: (value) => ref.read(playerPreferencesProvider.notifier).setFastAnimations(value),
              ),
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
    // Each seat owns half the row and scales down on narrow phones instead of
    // overflowing (4 players on a 360px screen).
    Widget seat(LudoSeatView? view, Alignment alignment) => Expanded(
          child: Align(
            alignment: alignment,
            child: view == null
                ? null
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: alignment,
                    child: LudoSeat(seat: view, onWarningSecond: view.participant.userId == warnUserId ? onWarningSecond : null),
                  ),
          ),
        );
    return SizedBox(
      height: 108,
      child: Row(children: [seat(left, Alignment.centerLeft), const SizedBox(width: 8), seat(right, Alignment.centerRight)]),
    );
  }
}

class _BannerData {
  const _BannerData(this.text, this.color, {this.mine = false});
  final String text;
  final Color color;
  final bool mine;
}

/// "YOUR TURN" / "SAMUEL'S TURN" pill in the current player's color. Pulses
/// when it is my move so it is impossible to miss.
class _TurnBanner extends StatefulWidget {
  const _TurnBanner({required this.banner});
  final _BannerData banner;

  @override
  State<_TurnBanner> createState() => _TurnBannerState();
}

class _TurnBannerState extends State<_TurnBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _TurnBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banner.mine != widget.banner.mine) _sync();
  }

  void _sync() => widget.banner.mine ? _pulse.repeat(reverse: true) : (_pulse..stop()..value = 0);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = widget.banner;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: Tween(begin: 0.85, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: AnimatedBuilder(
        key: ValueKey(banner.text),
        animation: _pulse,
        builder: (context, child) => Transform.scale(scale: 1 + _pulse.value * 0.05, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: banner.color,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
            boxShadow: [BoxShadow(color: banner.color.withValues(alpha: 0.6), blurRadius: 14)],
          ),
          child: Text(
            banner.text,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }
}

/// Deep navy table with a faint scattered-dice pattern.
class _TableBackdrop extends CustomPainter {
  const _TableBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1530), Color(0xFF13306B), Color(0xFF0B1530)],
        ).createShader(rect),
    );
    final tile = Paint()..color = Colors.white.withValues(alpha: 0.035);
    final pip = Paint()..color = Colors.white.withValues(alpha: 0.05);
    const step = 74.0;
    canvas.save();
    canvas.rotate(-0.35);
    for (var y = -size.height; y < size.height * 1.6; y += step) {
      for (var x = -size.width; x < size.width * 1.6; x += step) {
        final offset = ((y / step).round().isEven) ? 0.0 : step / 2;
        final r = Rect.fromLTWH(x + offset, y, 34, 34);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(8)), tile);
        canvas.drawCircle(r.center, 3.2, pip);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TableBackdrop oldDelegate) => false;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.unread,
    required this.soundOn,
    required this.recovering,
    required this.onExit,
    required this.onChat,
    required this.onToggleSound,
    required this.onMenu,
  });

  final int unread;
  final bool soundOn;
  final bool recovering;
  final VoidCallback onExit;
  final VoidCallback onChat;
  final VoidCallback onToggleSound;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    Widget pill({required Widget child, VoidCallback? onTap, String? tooltip}) => Tooltip(
          message: tooltip ?? '',
          child: Material(
            color: Colors.white.withValues(alpha: 0.1),
            shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), child: child),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(children: [
        pill(
          onTap: onExit,
          tooltip: 'Exit match',
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chevron_left_rounded, size: 18, color: Color(0xFFFF7A7A)),
            Text('Exit', style: TextStyle(color: Color(0xFFFF7A7A), fontWeight: FontWeight.w700)),
          ]),
        ),
        const Spacer(),
        pill(
          onTap: onToggleSound,
          tooltip: soundOn ? 'Mute sounds' : 'Unmute sounds',
          child: Icon(soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 8),
        pill(
          onTap: onChat,
          tooltip: 'Match chat',
          child: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        pill(
          onTap: onMenu,
          tooltip: 'Menu',
          child: recovering
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.more_horiz_rounded, size: 18, color: Colors.white),
        ),
      ]),
    );
  }
}

class _MatchChatSheet extends ConsumerWidget {
  const _MatchChatSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(matchChatControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(children: [
                Expanded(child: Text('Match chat', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Expanded(
              child: chat.loading && chat.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ChatThread(
                      lines: [
                        for (final m in chat.messages)
                          ChatLine(
                            id: m.id,
                            text: m.text,
                            senderName: m.sender.displayName,
                            mine: m.sender.userId == me,
                            createdAt: m.createdAt,
                          ),
                      ],
                      sending: chat.sending,
                      error: chat.error,
                      emptyText: 'Say good luck 👋',
                      onSend: ref.read(matchChatControllerProvider.notifier).send,
                    ),
            ),
          ],
        ),
      ),
    );
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
