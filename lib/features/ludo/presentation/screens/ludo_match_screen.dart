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
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/variant_picker.dart';
import 'package:friends_game_app/features/ludo/application/ludo_feedback.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_scene.dart';
import 'package:friends_game_app/features/ludo/application/ludo_timeline_controller.dart';
import 'package:friends_game_app/features/match/application/match_reactions_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/match_presenter.dart';
import 'package:friends_game_app/features/match/presentation/widgets/celebration.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';
import 'package:friends_game_app/features/match/presentation/match_sheets.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_back_guard.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_chrome.dart';
import 'package:friends_game_app/features/match/presentation/widgets/table_backdrop.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/turn_banner.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

/// In-match screen. Layout works for 2, 3 or 4 players: the board is rotated
/// so the viewer's color sits bottom-left, and every player has a corner seat
/// (avatar, turn ring, own dice). All game outcomes come from the server; the
/// screen only presents them, in order, through the timeline.
class LudoMatchScreen extends ConsumerStatefulWidget {
  const LudoMatchScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<LudoMatchScreen> createState() => _LudoMatchScreenState();
}

class _LudoMatchScreenState extends ConsumerState<LudoMatchScreen> with WidgetsBindingObserver {
  String? _pendingTokenId;

  /// Last token-home confetti (color + timeline sequence).
  ({LudoColor color, int seq})? _homeBurst;

  /// Full-screen win moment, shown once when the result is presented.
  bool _celebrating = false;
  Timer? _celebrationTimer;

  /// Short explanation after a tap that could not act (never fail silently).
  String? _nudge;
  Timer? _nudgeTimer;

  /// "Your turn" is pinged once per turn, keyed by match + state version.
  String? _lastTurnPing;

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

  String? get _me => ref.read(authControllerProvider).user?.id;

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

  void _play(LudoFeedback feedback) {
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

  /// A scene started (or the timeline went idle): sounds, bursts, celebration.
  void _onTimeline(LudoTimelineState? previous, LudoTimelineState next) {
    if (previous != null && next.epoch != previous.epoch) {
      // Recovery / rejoin: whatever was mid-flight is gone, including the win moment.
      _celebrationTimer?.cancel();
      if (_celebrating || _homeBurst != null) {
        setState(() {
          _celebrating = false;
          _homeBurst = null;
        });
      }
    }
    final scene = next.current;
    if (scene != null && next.sequence != previous?.sequence) {
      _play(sceneStartFeedback(scene, me: _me, fromOptimisticTap: next.currentFromOptimisticTap));
      if (scene is LudoFinishScene) {
        final color = next.presented?.game.tokenById(scene.tokenId)?.color;
        if (color != null) setState(() => _homeBurst = (color: color, seq: next.sequence));
      }
      if (scene is LudoMatchEndScene && !_celebrating) {
        setState(() => _celebrating = true);
        _celebrationTimer?.cancel();
        _celebrationTimer = Timer(const Duration(milliseconds: 2800), _endCelebration);
      }
    }
    _maybePingMyTurn();
  }

  void _maybePingMyTurn() {
    final timeline = ref.read(ludoTimelineProvider);
    final match = ref.read(ludoMatchControllerProvider);
    final game = match.snapshot?.game;
    if (game == null) return;
    if (!shouldPingMyTurn(authoritative: game, timelineIdle: timeline.idle, me: _me)) return;
    final key = '${match.matchId}:${game.version}';
    if (_lastTurnPing == key) return;
    _lastTurnPing = key;
    _play(const LudoFeedback(sound: GameSound.yourTurn, haptic: LudoHaptic.light));
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
    // The die clicks and spins at the tap; the server's face lands when its scene plays.
    ref.read(gameSoundServiceProvider).play(GameSound.diceRoll);
    final controller = ref.read(ludoMatchControllerProvider.notifier);
    if (startRoll) {
      await controller.rollForStart();
    } else {
      await controller.roll();
    }
  }

  void _completeScene(int sequence) => ref.read(ludoTimelineProvider.notifier).completeScene(sequence);

  @override
  Widget build(BuildContext context) => MatchBackGuard(onBack: () => _onSystemBack(context), child: _screen(context));

  /// Phone back: ask before leaving a live match; a finished one opens its result.
  void _onSystemBack(BuildContext context) {
    final game = ref.read(ludoMatchControllerProvider).snapshot?.game;
    if (game == null) {
      context.go(GameRoutes.lobby(GameCodes.ludo));
      return;
    }
    _confirmExit(context, game);
  }

  Widget _screen(BuildContext context) {
    ref.listen(ludoTimelineProvider, _onTimeline);
    ref.listen(ludoMatchControllerProvider.select((s) => s.snapshot?.game.version), (_, __) => _maybePingMyTurn());
    ref.listen(matchReactionsProvider, (previous, next) {
      final me = _me;
      final fresh = next.entries.any((e) => e.key != me && previous?[e.key]?.seq != e.value.seq);
      if (fresh) ref.read(gameSoundServiceProvider).play(GameSound.tick, volume: 0.5);
    });
    ref.listen(ludoMatchControllerProvider.select((s) => s.autoPlayNotice), (previous, next) {
      if (next == null || next.seq == previous?.seq) return;
      final me = _me;
      final left = next.maxStrikes - next.strikes;
      final name = ref
              .read(ludoMatchControllerProvider)
              .participants
              .where((p) => p.userId == next.playerId)
              .firstOrNull
              ?.displayLabel() ??
          'A player';
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
    final timeline = ref.watch(ludoTimelineProvider);
    final chat = ref.watch(matchChatControllerProvider);
    final reactions = ref.watch(matchReactionsProvider);
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

    final view = MatchPresenter(
      match: match,
      timeline: timeline,
      me: me,
      connected: socket == GameSocketStatus.connected,
      pendingTokenId: _pendingTokenId,
    );
    final game = view.game;
    final seats = view.seats(
      reactions: reactions,
      onRoll: (startRoll) => _rollMine(startRoll: startRoll),
      onDiceSettled: _completeScene,
    );
    LudoSeatView? seatAt(LudoCorner corner) => seats.where((seat) => seat.corner == corner).firstOrNull;
    final hint = _nudge ?? view.hint;

    final tokenOwners = {
      for (final player in view.game.players)
        for (final token in player.tokens) token.id: token.ownerId,
    };
    final walking = view.walking;
    final capturing = view.capturing;
    final sequence = timeline.sequence;

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
                    onChat: () => openMatchChat(context, ref),
                    onReact: () => showMatchReactionPicker(context, ref),
                    onToggleSound: () => ref.read(playerPreferencesProvider.notifier).setSound(!soundOn),
                    onMenu: () => _openMenu(context, match),
                    // The match's type (መመለስ ያለበት / የሌለበት / የረሳ ይሸነፋል); tap for what each means.
                    badge: switch (GameVariants.find(game.rulesVersion)) {
                      final variant? => GestureDetector(
                          onTap: () => showGameTypes(context, GameCodes.ludo),
                          child: VariantTag(variant: variant, emphasized: true),
                        ),
                      null => null,
                    },
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
                                board: view.board,
                                orientation: view.orientation,
                                walk: walking == null
                                    ? null
                                    : LudoWalkPresentation(
                                        move: walking.move,
                                        path: walking.path,
                                        sequence: sequence,
                                        duration: timeline.scale(walking.nominal),
                                        onStep: (_) => _play(stepFeedback(walking, me: me)),
                                        onCompleted: () {
                                          _play(landingFeedback(walking, me: me, board: view.board, tokenOwners: tokenOwners));
                                          _completeScene(sequence);
                                        },
                                      ),
                                capture: capturing == null
                                    ? null
                                    : LudoCapturePresentation(
                                        tokenIds: capturing.capturedTokenIds,
                                        sequence: sequence,
                                        duration: timeline.scale(capturing.nominal),
                                        onCompleted: () => _completeScene(sequence),
                                      ),
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
                            // No ticking while the board is still catching up with the server.
                            onWarningSecond: timeline.blocking || timeline.isCatchingUp
                                ? null
                                : () => ref.read(gameSoundServiceProvider).play(GameSound.tick, volume: 0.6),
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
                      if (game.phase == LudoMatchPhase.finished && !timeline.busy) ...[
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => context.pushReplacement(GameRoutes.result(GameCodes.ludo, widget.matchId)),
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
      context.pushReplacement(GameRoutes.result(GameCodes.ludo, widget.matchId));
      return;
    }
    final leave = await confirmLeaveMatch(context, widget.matchId);
    if (leave != true || !context.mounted) return;
    final ok = await ref.read(ludoMatchControllerProvider.notifier).resign();
    if (ok && context.mounted) context.go(GameRoutes.lobby(GameCodes.ludo));
  }

  Future<void> _confirmResign(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign match?'),
        content: const Text('Resigning ends your participation; the other players carry on, and your stake is lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Resign')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(ludoMatchControllerProvider.notifier).resign();
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
