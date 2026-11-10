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
import 'package:friends_game_app/features/dama/application/dama_match_controller.dart';
import 'package:friends_game_app/features/dama/application/dama_selection.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/dama/presentation/dama_presenter.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_board.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_paint.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_seat.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/match/application/match_reactions_controller.dart';
import 'package:friends_game_app/features/match/presentation/match_sheets.dart';
import 'package:friends_game_app/features/match/presentation/widgets/celebration.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_chrome.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

/// Live Dama match. The server decides everything; this screen shows the
/// board, lets the player pick one of the legal moves, and celebrates.
class DamaMatchScreen extends ConsumerStatefulWidget {
  const DamaMatchScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<DamaMatchScreen> createState() => _DamaMatchScreenState();
}

class _DamaMatchScreenState extends ConsumerState<DamaMatchScreen> with WidgetsBindingObserver {
  DamaSelection _selection = DamaSelection.none;

  /// Legal moves the current selection was made from (reset when they change).
  List<DamaMove> _selectionBase = const [];
  bool _lastMovePromoted = false;
  bool _celebrating = false;
  Timer? _celebrationTimer;
  String? _nudge;
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(gameSoundServiceProvider).preload();
    Future.microtask(() => ref.read(damaMatchControllerProvider.notifier).join(widget.matchId));
    Future.microtask(() => ref.read(matchChatControllerProvider.notifier).load(widget.matchId));
    Future.microtask(() => ref.read(matchReactionsProvider.notifier).attach(widget.matchId));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(ref.read(damaMatchControllerProvider.notifier).recover());
  }

  @override
  void dispose() {
    _celebrationTimer?.cancel();
    _nudgeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _play(GameSound sound, {double volume = 1}) => ref.read(gameSoundServiceProvider).play(sound, volume: volume);

  void _haptic(void Function() effect) {
    if (ref.read(playerPreferencesProvider).hapticsEnabled) effect();
  }

  void _explain(String? text) {
    if (text == null) return;
    _haptic(HapticFeedback.selectionClick);
    _nudgeTimer?.cancel();
    setState(() => _nudge = text);
    _nudgeTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _nudge = null);
    });
  }

  void _onTap(DamaPresenter view, int square) {
    if (!view.canAct) return _explain(view.tapExplanation);
    final result = DamaPicker.tap(view.legal, _selection, square);
    if (result.send case final move?) {
      _haptic(HapticFeedback.lightImpact);
      setState(() => _selection = DamaSelection.none);
      ref.read(damaMatchControllerProvider.notifier).move(move);
      return;
    }
    if (result.selection.isEmpty && _selection.isEmpty) return _explain(view.tapExplanation);
    _haptic(HapticFeedback.selectionClick);
    setState(() => _selection = result.selection);
  }

  /// Sounds and moments when the server's game moves on.
  void _onGameChanged(DamaGame? previous, DamaGame? next) {
    if (previous == null || next == null || next.version <= previous.version) return;
    final me = ref.read(authControllerProvider).user?.id;
    final moved = next.lastMove != null && next.lastMove != previous.lastMove;
    if (moved) {
      final mover = previous.pieceAt(next.lastMove!.from);
      _lastMovePromoted = mover != null && !mover.king && next.pieceAt(next.lastMove!.to)?.king == true;
      if (_lastMovePromoted) {
        Future.delayed(Duration(milliseconds: _hopMs * (next.lastMove!.path.length - 1)), () {
          if (mounted) _play(GameSound.home);
        });
      }
    }
    if (next.finished && !previous.finished) {
      final delay = moved ? _hopMs * next.lastMove!.path.length : 0;
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted) return;
        _play(next.isDraw
            ? GameSound.home
            : next.winnerId == me
                ? GameSound.win
                : GameSound.lose);
        setState(() => _celebrating = true);
        _celebrationTimer?.cancel();
        _celebrationTimer = Timer(const Duration(milliseconds: 2800), _endCelebration);
      });
    } else if (next.currentPlayerId == me && previous.currentPlayerId != me) {
      _play(GameSound.yourTurn, volume: 0.7);
    }
  }

  void _endCelebration() {
    if (mounted && _celebrating) setState(() => _celebrating = false);
  }

  int get _hopMs => ref.read(playerPreferencesProvider).fastAnimations ? 150 : 230;

  @override
  Widget build(BuildContext context) {
    ref.listen<DamaGame?>(damaMatchControllerProvider.select((s) => s.game), _onGameChanged);
    ref.listen(damaMatchControllerProvider.select((s) => s.autoPlayNotice), (previous, next) {
      if (next == null || next.seq == previous?.seq) return;
      final me = ref.read(authControllerProvider).user?.id;
      final left = next.maxStrikes - next.strikes;
      final name = ref.read(damaMatchControllerProvider).participant(next.playerId)?.shortName ?? 'Opponent';
      final text = next.playerId == me
          ? 'Time ran out, so we played for you (${next.strikes}/${next.maxStrikes}).${left > 0 ? ' $left more and you forfeit.' : ''}'
          : '$name is away, auto-played (${next.strikes}/${next.maxStrikes}).';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
    });
    ref.listen(matchReactionsProvider, (previous, next) {
      final me = ref.read(authControllerProvider).user?.id;
      if (next.entries.any((e) => e.key != me && previous?[e.key]?.seq != e.value.seq)) _play(GameSound.safe, volume: 0.45);
    });

    final match = ref.watch(damaMatchControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    final socket = ref.watch(gameSocketStatusProvider);
    final chat = ref.watch(matchChatControllerProvider);
    final reactions = ref.watch(matchReactionsProvider);
    final soundOn = ref.watch(playerPreferencesProvider.select((p) => p.soundEnabled));

    if (match.loading || match.game == null) {
      return _Loading(error: match.error, onRetry: () => ref.read(damaMatchControllerProvider.notifier).join(widget.matchId));
    }

    final view = DamaPresenter(match: match, me: me, connected: socket == GameSocketStatus.connected);
    final game = view.game;

    // A selection only lives as long as the legal moves it was made from.
    if (!identical(_selectionBase, view.legal)) {
      _selectionBase = view.legal;
      _selection = DamaPicker.initial(view.legal);
    }

    DamaSeat seat(String? userId, {required bool isMe}) {
      final color = game.colorOf(userId) ?? (isMe ? view.myColor : view.myColor.opponent);
      final reaction = reactions[userId];
      final active = !game.finished && game.currentPlayerId == userId;
      return DamaSeat(
        name: match.participant(userId)?.shortName ?? (isMe ? 'You' : 'Opponent'),
        color: color,
        isMe: isMe,
        active: active,
        captured: game.capturedBy(color),
        turnEndsAt: active ? match.timing.turnEndsAt : null,
        turnSeconds: match.turnSeconds,
        strikes: match.timing.strikes[userId] ?? 0,
        maxStrikes: match.timing.maxStrikes,
        reaction: reaction?.reaction.display,
        reactionSeq: reaction?.seq ?? 0,
        onWarningSecond: isMe ? () => _play(GameSound.tick, volume: 0.6) : null,
      );
    }

    final hint = _nudge ?? view.hint;
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: DamaPalette.tableBottom,
        body: Stack(children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(0, -0.2), radius: 1.2, colors: [DamaPalette.tableTop, DamaPalette.tableBottom]),
              ),
            ),
          ),
          SafeArea(
            child: Column(children: [
              MatchConnectionBanner(status: socket, recovering: match.recovering),
              MatchTopBar(
                unread: chat.unread,
                soundOn: soundOn,
                recovering: match.recovering,
                onExit: () => _exit(context, game),
                onChat: () => openMatchChat(context, ref),
                onReact: () => showMatchReactionPicker(context, ref),
                onToggleSound: () => ref.read(playerPreferencesProvider.notifier).setSound(!soundOn),
                onMenu: () => _openMenu(context, match),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  // Seats, banner and board stay together like a table, centred
                  // in the free space; on small phones the board shrinks.
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    seat(view.opponentId, isMe: false),
                    const SizedBox(height: 12),
                    _Banner(text: view.banner, urgent: view.mustCapture),
                    const SizedBox(height: 10),
                    Flexible(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DamaBoard(
                          board: game.board,
                          version: game.version,
                          flipped: view.flipped,
                          lastMove: game.lastMove,
                          lastMovePromoted: _lastMovePromoted,
                          selection: _selection,
                          targets: DamaPicker.targets(view.legal, _selection),
                          movable: DamaPicker.movable(view.legal),
                          mustCapture: view.mustCapture && view.canAct,
                          onTapSquare: (square) => _onTap(view, square),
                          onHop: (capture) => _play(capture ? GameSound.capture : GameSound.step, volume: capture ? 1 : 0.5),
                          hopMs: _hopMs,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    seat(me, isMe: true),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (match.error != null) MatchInlineMessage(message: match.error!),
                  SizedBox(
                    height: 20,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        hint,
                        key: ValueKey(hint),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (!game.finished && view.pliesBeforeDraw <= 10)
                    Text(
                      'Draw in ${view.pliesBeforeDraw} moves without a capture',
                      style: const TextStyle(color: DamaPalette.goldLight, fontSize: 12),
                    ),
                  if (game.finished) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => context.pushReplacement(GameRoutes.result(GameCodes.dama, widget.matchId)),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('View result'),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
          if (_celebrating) Positioned.fill(child: WinCelebration(title: view.banner, subtitle: view.hint, onDismiss: _endCelebration)),
        ]),
      ),
    );
  }

  Future<void> _exit(BuildContext context, DamaGame game) async {
    if (game.finished) {
      context.pushReplacement(GameRoutes.result(GameCodes.dama, widget.matchId));
      return;
    }
    if (!await confirmLeaveMatch(context) || !context.mounted) return;
    final ok = await ref.read(damaMatchControllerProvider.notifier).resign();
    if (ok && context.mounted) context.go('/home');
  }

  Future<void> _openMenu(BuildContext context, DamaMatchViewState match) async {
    final finished = match.game?.finished ?? true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (match.sessionCode case final code? when code.isNotEmpty)
            ListTile(leading: const Icon(Icons.tag_rounded), title: Text('Game $code'), subtitle: const Text('Session code')),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('How to play'),
            onTap: () {
              Navigator.pop(sheet);
              showDamaRules(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Sync game'),
            onTap: () {
              Navigator.pop(sheet);
              ref.read(damaMatchControllerProvider.notifier).recover();
            },
          ),
          if (!finished)
            ListTile(
              leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Resign', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                Navigator.pop(sheet);
                if (await confirmLeaveMatch(context)) await ref.read(damaMatchControllerProvider.notifier).resign();
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
        ]),
      ),
    );
  }
}

/// The rules in plain words (also reachable from the lobby).
Future<void> showDamaRules(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: const [
            Text('How to play Dama', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            _Rule(Icons.grid_on_rounded, 'Dark squares only', '12 pieces each. Light moves first.'),
            _Rule(Icons.north_east_rounded, 'Men step forward', 'One square diagonally forward onto an empty square.'),
            _Rule(Icons.bolt_rounded, 'Capture is compulsory',
                'Jump an enemy piece next to you, forward or backward. Keep jumping while you can.'),
            _Rule(Icons.format_list_numbered_rounded, 'Take the most',
                'If several captures exist you must take the one with the most pieces.'),
            _Rule(Icons.workspace_premium_rounded, 'Kings fly',
                'A man that ends on the far row is crowned. Kings slide any distance and capture from afar.'),
            _Rule(Icons.emoji_events_outlined, 'Winning', 'Take all enemy pieces, or leave your opponent with no move.'),
            _Rule(Icons.handshake_outlined, 'Draw', '20 moves each with no capture and no man moving is a draw; stakes are returned.'),
          ],
        ),
      ),
    );

class _Rule extends StatelessWidget {
  const _Rule(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(text),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.urgent});
  final String text;
  final bool urgent;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
        child: Container(
          key: ValueKey(text),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: (urgent ? DamaPalette.mustCapture : DamaPalette.gold).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: urgent ? DamaPalette.mustCapture : DamaPalette.gold),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
        ),
      );
}

class _Loading extends StatelessWidget {
  const _Loading({required this.error, required this.onRetry});
  final String? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Dama')),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: onRetry, child: const Text('Try again')),
                  ]),
                ),
        ),
      );
}
