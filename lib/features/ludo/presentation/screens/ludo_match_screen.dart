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
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_feedback.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/match/application/match_reactions_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/match_presenter.dart';
import 'package:friends_game_app/features/match/presentation/widgets/celebration.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_chat_sheet.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_chrome.dart';
import 'package:friends_game_app/features/match/presentation/widgets/table_backdrop.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/turn_banner.dart';
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

  /// Last token-home confetti (color + presentation sequence).
  ({LudoColor color, int seq})? _homeBurst;

  /// Full-screen win moment, shown once when the result is presented.
  bool _celebrating = false;
  Timer? _celebrationTimer;

  /// Short explanation after a tap that could not act (never fail silently).
  String? _nudge;
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(gameSoundServiceProvider).preload();
    Future.microtask(() => ref.read(ludoMatchControllerProvider.notifier).join(widget.matchId));
    Future.microtask(() => ref.read(matchChatControllerProvider.notifier).load(widget.matchId));
    Future.microtask(() => ref.read(matchReactionsProvider.notifier).attach(widget.matchId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(ludoMatchControllerProvider.notifier).recover(reason: 'app_resume'));
    }
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _celebrationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The board was tapped where nothing can act: say why (never fail silently).
  void _explainTap(String? text) {
    if (text == null) return;
    _tick();
    _nudgeTimer?.cancel();
    setState(() => _nudge = text);
    _nudgeTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _nudge = null);
    });
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

    if (event.kind == LudoPresentationKind.finish && event.tokenId != null) {
      final color = snapshot?.game.tokenById(event.tokenId!)?.color;
      if (color != null) setState(() => _homeBurst = (color: color, seq: next.sequence));
    }
    if (event.kind == LudoPresentationKind.matchFinished && !_celebrating) {
      setState(() => _celebrating = true);
      _celebrationTimer?.cancel();
      _celebrationTimer = Timer(const Duration(milliseconds: 2800), _endCelebration);
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

  void _endCelebration() {
    if (mounted && _celebrating) setState(() => _celebrating = false);
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
    ref.listen(matchReactionsProvider, (previous, next) {
      final me = ref.read(authControllerProvider).user?.id;
      final fresh = next.entries.any((e) => e.key != me && previous?[e.key]?.seq != e.value.seq);
      if (fresh) ref.read(gameSoundServiceProvider).play(GameSound.safe, volume: 0.45);
    });
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
    ref.watch(matchReactionsProvider); // seats show live reactions
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
    final view = MatchPresenter(
      match: match,
      me: me,
      animation: animation,
      connected: socket == GameSocketStatus.connected,
      pendingTokenId: _pendingTokenId,
    );
    final seats = view.seats(
      SeatPresentation(
        presentedDice: _presentedDice,
        diceKeys: _diceKeys,
        rollHistory: _rollHistory,
        reactions: ref.read(matchReactionsProvider),
        mySpin: _mySpin,
      ),
      onRoll: (startRoll) => _rollMine(startRoll: startRoll),
    );
    LudoSeatView? seatAt(LudoCorner corner) => seats.where((seat) => seat.corner == corner).firstOrNull;
    final hint = _nudge ?? view.hint;

    // The match is always presented on the dark game table, regardless of the
    // app theme, like a dedicated game screen.
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1530),
        body: Stack(
          children: [
            const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: TableBackdrop()))),
            SafeArea(
              child: Column(
                children: [
                  MatchConnectionBanner(status: socket, recovering: match.recovering),
                  MatchTopBar(
                    unread: chat.unread,
                    soundOn: soundOn,
                    recovering: match.recovering,
                    onExit: () => _confirmExit(context, game),
                    onChat: () => _openChat(context),
                    onReact: () => _openReactions(context),
                    onToggleSound: () => ref.read(playerPreferencesProvider.notifier).setSound(!soundOn),
                    onMenu: () => _openMenu(context, match),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          LudoSeatRow(left: seatAt(LudoCorner.topLeft), right: seatAt(LudoCorner.topRight)),
                          const SizedBox(height: 6),
                          TurnBanner(banner: view.banner),
                          if (game.tokensToWin < 4) ...[
                            const SizedBox(height: 4),
                            MatchGoalChip(tokensToWin: game.tokensToWin),
                          ],
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: LudoBoard(
                                tokens: view.tokens(onMove: _moveToken),
                                orientation: view.orientation,
                                animatedMove: view.walkingMove,
                                animationSequence: animation.sequence,
                                onStep: () => ref.read(gameSoundServiceProvider).play(GameSound.step, volume: 0.5),
                                ghosts: view.ghosts(onMove: _moveToken),
                                onBoardTap: () => _explainTap(view.tapExplanation),
                                homeBurst: _homeBurst,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          LudoSeatRow(
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
                      if (match.error != null) MatchInlineMessage(message: match.error!),
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
                      if (game.phase == LudoMatchPhase.finished && !animation.busy) ...[
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
            if (_celebrating)
              Positioned.fill(
                child: WinCelebration(
                  title: view.banner.text,
                  subtitle: game.tokensToWin < 4 ? 'First to ${game.tokensToWin} home' : 'All 4 tokens home',
                  onDismiss: _endCelebration,
                ),
              ),
          ],
        ),
      ),
    );
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

  Future<void> _openReactions(BuildContext context) async {
    final reaction = await showModalBottomSheet<MatchReaction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final r in MatchReaction.values)
                ActionChip(
                  label: Text(r.display, style: TextStyle(fontSize: r.isEmoji ? 22 : 14, fontWeight: FontWeight.w700)),
                  onPressed: () => Navigator.pop(context, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (reaction != null) await ref.read(matchReactionsProvider.notifier).send(reaction);
  }

  Future<void> _openChat(BuildContext context) async {
    final controller = ref.read(matchChatControllerProvider.notifier);
    controller.setPanelOpen(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const MatchChatSheet(),
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
