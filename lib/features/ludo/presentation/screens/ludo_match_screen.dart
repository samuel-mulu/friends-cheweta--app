import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_player_dice_panel.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_player_identity_bar.dart';

class LudoMatchScreen extends ConsumerStatefulWidget {
  const LudoMatchScreen({super.key, required this.matchId});
  final String matchId;

  @override
  ConsumerState<LudoMatchScreen> createState() => _LudoMatchScreenState();
}

class _LudoMatchScreenState extends ConsumerState<LudoMatchScreen> with WidgetsBindingObserver {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() => _now = ref.read(gameSocketServiceProvider).serverNow());
    });
    Future.microtask(() => ref.read(ludoMatchControllerProvider.notifier).join(widget.matchId));
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
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(ludoMatchControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final socket = ref.watch(gameSocketStatusProvider);
    final animation = ref.watch(ludoAnimationQueueProvider);
    final snapshot = match.snapshot;

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
                    FilledButton(onPressed: () => ref.read(ludoMatchControllerProvider.notifier).join(widget.matchId), child: const Text('Try again')),
                  ]),
                ),
        ),
      );
    }

    final game = snapshot.game;
    final me = auth.user?.id;
    final myTurn = me != null && game.currentPlayerId == me;
    final canStartRoll = game.phase == LudoMatchPhase.preGame &&
        game.turnPhase == LudoTurnPhase.startRoll &&
        me != null &&
        snapshot.startingRoll.candidatePlayerIds.contains(me) &&
        !snapshot.startingRoll.rolls.containsKey(me) &&
        match.pendingCommandId == null;
    final canRoll = game.phase == LudoMatchPhase.playing &&
        game.turnPhase == LudoTurnPhase.waitingForRoll &&
        myTurn &&
        match.pendingCommandId == null;

    final tokens = <LudoBoardTokenView>[];
    for (final player in game.players) {
      for (var i = 0; i < player.tokens.length; i++) {
        final token = player.tokens[i];
        final legal = me == token.ownerId && game.legalTokenIds.contains(token.id) && match.pendingCommandId == null;
        final capturedEffect = animation.current?.kind == LudoPresentationKind.capture && animation.current!.tokenIds.contains(token.id);
        tokens.add(LudoBoardTokenView(
          id: token.id,
          color: token.color,
          progress: token.progress,
          baseIndex: i,
          highlighted: legal,
          emphasized: capturedEffect,
          onTap: legal ? () => ref.read(ludoMatchControllerProvider.notifier).move(token.id) : null,
        ));
      }
    }

    final remaining = _remaining(match.timing?.turnEndsAt);
    final dicePair = _resolveDicePair(
      snapshot: snapshot,
      participants: match.participants,
      myUserId: me,
      lastDiceByPlayer: match.lastDiceByPlayer,
      animation: animation.current,
      animationSequence: animation.sequence,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Ludo · ${_shortId(widget.matchId)}'),
        actions: [
          IconButton(
            tooltip: 'Sync game',
            onPressed: match.recovering ? null : () => ref.read(ludoMatchControllerProvider.notifier).recover(reason: 'manual_refresh'),
            icon: match.recovering
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _ConnectionBanner(status: socket, recovering: match.recovering),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 8, AppSpacing.screen, 24),
                children: [
                  _PlayersHeader(
                    snapshot: snapshot,
                    participants: match.participants,
                    myUserId: me,
                    remaining: remaining,
                    timingEstimated: match.timing?.estimated == true,
                  ),
                  const SizedBox(height: 12),
                  LudoPlayerIdentityBar(
                    participants: match.participants,
                    snapshot: snapshot,
                    myUserId: me,
                    currentPlayerId: game.currentPlayerId,
                  ),
                  const SizedBox(height: 14),
                  LudoBoard(
                    tokens: tokens,
                    animatedMove: animation.current?.kind == LudoPresentationKind.move ? animation.current?.move : null,
                    animationSequence: animation.sequence,
                  ),
                  const SizedBox(height: 18),
                  if (match.error != null) ...[
                    _InlineMessage(message: match.error!),
                    const SizedBox(height: 12),
                  ],
                  _ActionPanel(
                    snapshot: snapshot,
                    participants: match.participants,
                    myUserId: me,
                    busy: match.pendingCommandId != null,
                    canStartRoll: canStartRoll,
                    canRoll: canRoll,
                    dicePair: dicePair,
                    onStartRoll: () => ref.read(ludoMatchControllerProvider.notifier).rollForStart(),
                    onRoll: () => ref.read(ludoMatchControllerProvider.notifier).roll(),
                    onResign: () => _confirmResign(context),
                  ),
                  if (game.phase == LudoMatchPhase.finished) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => context.pushReplacement('/ludo/result/${widget.matchId}'),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('View result & settlement'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Duration? _remaining(DateTime? deadline) {
    if (deadline == null) return null;
    final value = deadline.difference(_now);
    return value.isNegative ? Duration.zero : value;
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

  String _shortId(String value) => value.length <= 8 ? value : value.substring(0, 8);
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

_PlayerDicePair? _resolveDicePair({
  required LudoRuntimeSnapshot snapshot,
  required List<LudoMatchParticipant> participants,
  required String? myUserId,
  required Map<String, int> lastDiceByPlayer,
  required LudoPresentationEvent? animation,
  required int animationSequence,
}) {
  final ordered = _orderedParticipants(participants, snapshot, myUserId);
  if (ordered.length < 2) return null;

  final mine = ordered[0];
  final opponent = ordered[1];

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
        ? 'Recovering authoritative match state…'
        : status == GameSocketStatus.connecting || status == GameSocketStatus.recovering
            ? 'Reconnecting…'
            : 'Connection lost. Your board is preserved while the server reconnects.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _PlayersHeader extends StatelessWidget {
  const _PlayersHeader({
    required this.snapshot,
    required this.participants,
    required this.myUserId,
    required this.remaining,
    required this.timingEstimated,
  });
  final LudoRuntimeSnapshot snapshot;
  final List<LudoMatchParticipant> participants;
  final String? myUserId;
  final Duration? remaining;
  final bool timingEstimated;

  String _nameFor(String? userId) {
    if (userId == null) return 'Player';
    for (final participant in participants) {
      if (participant.userId == userId) return participant.fullName;
    }
    return 'Player';
  }

  @override
  Widget build(BuildContext context) {
    final game = snapshot.game;
    final current = game.currentPlayerId;
    final currentName = current == myUserId ? 'Your turn' : '${_nameFor(current)}\'s turn';
    final secs = remaining?.inSeconds;
    return Row(
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              game.phase == LudoMatchPhase.preGame ? 'Starting roll' : currentName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 3),
            Text(_phaseText(game), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (secs != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
            child: Text('${secs}s${timingEstimated ? ' ~' : ''}', style: Theme.of(context).textTheme.labelLarge),
          ),
      ],
    );
  }

  String _phaseText(LudoGameState game) => switch (game.turnPhase) {
        LudoTurnPhase.startRoll => 'Both players roll to determine who starts.',
        LudoTurnPhase.waitingForRoll => 'Waiting for the authoritative server roll.',
        LudoTurnPhase.waitingForMove => 'Choose one of the highlighted legal tokens.',
        LudoTurnPhase.complete => 'Match complete.',
      };
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.snapshot,
    required this.participants,
    required this.myUserId,
    required this.busy,
    required this.canStartRoll,
    required this.canRoll,
    required this.dicePair,
    required this.onStartRoll,
    required this.onRoll,
    required this.onResign,
  });
  final LudoRuntimeSnapshot snapshot;
  final List<LudoMatchParticipant> participants;
  final String? myUserId;
  final bool busy;
  final bool canStartRoll;
  final bool canRoll;
  final _PlayerDicePair? dicePair;
  final VoidCallback onStartRoll;
  final VoidCallback onRoll;
  final VoidCallback onResign;

  @override
  Widget build(BuildContext context) {
    final game = snapshot.game;
    final isFinished = game.phase == LudoMatchPhase.finished;
    final canRollMine = canStartRoll || canRoll;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (dicePair != null)
              LudoPlayerDicePanel(
                myParticipant: dicePair!.mine,
                opponentParticipant: dicePair!.opponent,
                myDiceValue: dicePair!.myDiceValue,
                opponentDiceValue: dicePair!.opponentDiceValue,
                myAnimateKey: dicePair!.myAnimateKey,
                opponentAnimateKey: dicePair!.opponentAnimateKey,
                canRollMine: canRollMine,
                onRollMine: canStartRoll ? onStartRoll : onRoll,
                busy: busy,
              )
            else
              Text('Waiting for players…', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_headline(game), style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(_detail(game), style: Theme.of(context).textTheme.bodySmall),
                      if (busy) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                    ],
                  ),
                ),
                if (!isFinished)
                  IconButton(tooltip: 'Resign', onPressed: busy ? null : onResign, icon: const Icon(Icons.flag_outlined)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _headline(LudoGameState game) {
    if (game.phase == LudoMatchPhase.finished) return 'Match finished';
    if (game.phase == LudoMatchPhase.preGame) return canStartRoll ? 'Tap your dice to roll' : 'Waiting for starting rolls';
    if (game.turnPhase == LudoTurnPhase.waitingForMove) {
      return game.currentPlayerId == myUserId ? 'Choose a token' : '${_playerName(game.currentPlayerId)} is choosing';
    }
    return game.currentPlayerId == myUserId ? 'Roll your dice when ready' : '${_playerName(game.currentPlayerId)} is playing';
  }

  String _playerName(String? userId) {
    if (userId == null) return 'Opponent';
    if (userId == myUserId) return 'You';
    for (final participant in participants) {
      if (participant.userId == userId) return participant.fullName;
    }
    return 'Opponent';
  }

  String _detail(LudoGameState game) {
    if (game.phase == LudoMatchPhase.finished) {
      final won = game.winnerOrder.isNotEmpty && game.winnerOrder.first == myUserId;
      return won ? 'You won. Settlement is handled by the server.' : 'Result confirmed by the server.';
    }
    if (game.turnPhase == LudoTurnPhase.waitingForMove && game.currentPlayerId == myUserId) {
      return '${game.legalTokenIds.length} legal move${game.legalTokenIds.length == 1 ? '' : 's'} available.';
    }
    return 'Game state version ${game.version}';
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
        child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
      );
}
