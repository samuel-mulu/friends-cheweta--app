import 'package:flutter/painting.dart';
import 'package:friends_game_app/features/ludo/application/ludo_match_controller.dart';
import 'package:friends_game_app/features/ludo/application/ludo_scene.dart';
import 'package:friends_game_app/features/ludo/application/ludo_timeline_controller.dart';
import 'package:friends_game_app/features/match/application/match_reactions_controller.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_board_spec.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_seats.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_seat.dart';

/// Text + color of the "YOUR TURN" pill.
class TurnBannerData {
  const TurnBannerData(this.text, this.color, {this.mine = false});
  final String text;
  final Color color;
  final bool mine;
}

/// Pure mapping from match state to what the match screen shows: seats,
/// tokens, previews, banner and hints. No widgets, no IO, so it is unit tested
/// directly and the screen stays a thin layout.
///
/// Two snapshots feed it: the controller's *authoritative* one (what the player
/// may do) and the timeline's *presented* one (what the board shows). Input
/// opens only when they agree, so a token never glows before its dice landed.
class MatchPresenter {
  MatchPresenter({
    required this.match,
    required this.timeline,
    required this.me,
    required this.connected,
    this.pendingTokenId,
  }) : assert(match.snapshot != null, 'present a joined match only');

  final LudoMatchViewState match;
  final LudoTimelineState timeline;
  final String? me;

  /// Socket connected (recovery is read from [match]).
  final bool connected;

  /// Token I just tapped, until the server answers.
  final String? pendingTokenId;

  LudoRuntimeSnapshot get authoritative => match.snapshot!;

  /// What the board shows right now.
  LudoRuntimeSnapshot get snapshot => timeline.presented ?? authoritative;
  LudoGameState get game => snapshot.game;
  LudoBoardSpec get board => snapshot.board;

  late final List<LudoMatchParticipant> participants = withColors(match.participants, snapshot);
  late final LudoColor? myColor = participants.where((p) => p.userId == me).firstOrNull?.color;
  late final LudoBoardOrientation orientation = LudoBoardOrientation.forViewer(myColor);

  bool get online => connected && !match.recovering;

  /// No command in flight and the link is up.
  bool get actionsAllowed => match.pendingCommandId == null && online;

  /// The board has caught up with the server.
  bool get drained => timeline.idle && game.version >= authoritative.game.version;

  /// Input is invited only once the board shows the server's state.
  bool get canAct => actionsAllowed && !timeline.blocking && !timeline.isCatchingUp && drained;

  LudoMoveScene? get walking => switch (timeline.current) { final LudoMoveScene s => s, _ => null };
  LudoCaptureScene? get capturing => switch (timeline.current) { final LudoCaptureScene s => s, _ => null };
  LudoFinishScene? get finishing => switch (timeline.current) { final LudoFinishScene s => s, _ => null };

  // ---- seats

  List<LudoSeatView> seats({
    required Map<String, ShownReaction> reactions,
    required void Function(bool startRoll) onRoll,
    void Function(int sequence)? onDiceSettled,
  }) =>
      [for (final participant in participants) _seat(participant, reactions, onRoll, onDiceSettled)];

  LudoSeatView _seat(
    LudoMatchParticipant participant,
    Map<String, ShownReaction> reactions,
    void Function(bool) onRoll,
    void Function(int sequence)? onDiceSettled,
  ) {
    final userId = participant.userId;
    final isMe = userId == me;
    final preGame = game.phase == LudoMatchPhase.preGame;
    final startRolled = snapshot.startingRoll.rolls.containsKey(userId);
    final startCandidate = snapshot.startingRoll.candidatePlayerIds.contains(userId);
    final active =
        preGame ? startCandidate && !startRolled : game.currentPlayerId == userId && game.phase == LudoMatchPhase.playing;
    final resigned = snapshot.resignedPlayerIds.contains(userId);
    final rankIndex = game.winnerOrder.indexOf(userId);

    final canStartRoll = isMe && preGame && game.turnPhase == LudoTurnPhase.startRoll && startCandidate && !startRolled;
    final canRoll = isMe && !preGame && active && game.turnPhase == LudoTurnPhase.waitingForRoll;
    final diceScene = switch (timeline.current) { final LudoDiceScene s => s, _ => null };
    final rollingNow = diceScene != null && diceScene.playerId == userId;

    final diceState = rollingNow
        ? LudoDiceVisualState.rolling
        : (canStartRoll || canRoll) && canAct
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

    final reaction = reactions[userId];
    final sequence = timeline.sequence;
    return LudoSeatView(
      participant: participant,
      corner: orientation.cornerOf(participant.color ?? LudoColor.red),
      isMe: isMe,
      active: active,
      // Only faces the timeline has shown; a queued roll is never spoiled.
      diceValue: timeline.presentedDice[userId] ?? (preGame ? snapshot.startingRoll.rolls[userId] : null),
      diceKey: timeline.diceKeys[userId] ?? 0,
      spinning: isMe && timeline.spinningPlayerId == userId,
      diceState: diceState,
      diceSettleDuration: timeline.scale(LudoMotion.diceRoll),
      onDiceSettled: rollingNow && onDiceSettled != null ? () => onDiceSettled(sequence) : null,
      turnEndsAt: active ? match.timing?.turnEndsAt : null,
      turnSeconds: match.turnDurationSeconds,
      status: status,
      rank: rankIndex >= 0 && game.players.length > 2 ? rankIndex + 1 : (rankIndex == 0 ? 1 : null),
      resigned: resigned,
      recentRolls: timeline.rollHistory[userId] ?? const [],
      strikes: match.strikes[userId] ?? 0,
      reaction: reaction?.reaction.display,
      reactionSeq: reaction?.seq ?? 0,
      maxStrikes: match.maxStrikes,
      onRoll: canStartRoll || canRoll ? () => onRoll(canStartRoll) : null,
      tokensHome: game.tokensHome(userId),
      tokensToWin: game.tokensToWin,
    );
  }

  // ---- board

  bool get _myMove =>
      game.currentPlayerId == me && game.turnPhase == LudoTurnPhase.waitingForMove && pendingTokenId == null && canAct;

  List<LudoBoardTokenView> tokens({required void Function(String tokenId) onMove}) {
    final raw = <({LudoToken token, int baseIndex})>[
      for (final player in game.players)
        for (var i = 0; i < player.tokens.length; i++) (token: player.tokens[i], baseIndex: i),
    ];

    // Tokens sharing a cell are fanned out (stackIndex of stackCount).
    final groups = <String, List<String>>{};
    for (final item in raw) {
      final key = LudoBoardGeometry.occupancyKey(
        color: item.token.color,
        progress: item.token.progress,
        tokenId: item.token.id,
        board: board,
      );
      groups.putIfAbsent(key, () => []).add(item.token.id);
    }
    final stackOf = <String, (int, int)>{
      for (final ids in groups.values)
        for (var s = 0; s < ids.length; s++) ids[s]: (s, ids.length),
    };

    final legal = authoritative.game.legalTokenIds;
    final emphasized = capturing?.capturedTokenIds.toSet() ?? const <String>{};
    return [
      for (final item in raw)
        _tokenView(item.token, item.baseIndex, stackOf[item.token.id] ?? (0, 1), legal, emphasized, onMove),
    ];
  }

  LudoBoardTokenView _tokenView(
    LudoToken token,
    int baseIndex,
    (int, int) stack,
    List<String> legal,
    Set<String> emphasized,
    void Function(String) onMove,
  ) {
    final selectable = me == token.ownerId && legal.contains(token.id) && canAct && pendingTokenId == null;
    return LudoBoardTokenView(
      id: token.id,
      color: token.color,
      progress: token.progress,
      baseIndex: baseIndex,
      highlighted: selectable,
      emphasized: emphasized.contains(token.id),
      pending: pendingTokenId == token.id,
      finished: token.state == LudoTokenState.finished || board.isFinished(token.progress),
      stackIndex: stack.$1,
      stackCount: stack.$2,
      onTap: selectable ? () => onMove(token.id) : null,
    );
  }

  /// Landing previews while it is my move (the server computed them).
  List<LudoGhostView> ghosts({required void Function(String tokenId) onMove}) {
    final color = myColor;
    if (color == null || !_myMove) return const [];
    final legal = authoritative.game.legalTokenIds;
    return [
      for (final preview in match.legalMoves)
        if (legal.contains(preview.tokenId))
          LudoGhostView(
            tokenId: preview.tokenId,
            color: color,
            toProgress: preview.toProgress,
            captures: preview.captures.isNotEmpty,
            safe: preview.safe,
            onTap: () => onMove(preview.tokenId),
          ),
    ];
  }

  // ---- text

  TurnBannerData get banner {
    LudoMatchParticipant? find(String? id) => participants.where((p) => p.userId == id).firstOrNull;
    String name(String? id) => (find(id)?.displayLabel() ?? 'Opponent').toUpperCase();
    const gold = Color(0xFFFFC83D);

    if (timeline.isCatchingUp) return const TurnBannerData('CATCHING UP…', gold);

    if (game.phase == LudoMatchPhase.finished) {
      final winner = game.winnerOrder.firstOrNull;
      return TurnBannerData(winner == me ? 'YOU WON!' : '${name(winner)} WON', find(winner)?.color?.color ?? gold,
          mine: winner == me);
    }
    if (game.phase == LudoMatchPhase.preGame) {
      final start = snapshot.startingRoll;
      final mine = me != null && start.candidatePlayerIds.contains(me) && !start.rolls.containsKey(me);
      if (mine) {
        return TurnBannerData(start.round > 1 ? 'TIE! ROLL AGAIN' : 'ROLL TO START', find(me)?.color?.color ?? gold,
            mine: true);
      }
      return const TurnBannerData('WHO STARTS?', gold);
    }

    final current = game.currentPlayerId;
    final color = find(current)?.color?.color ?? gold;
    switch (timeline.current) {
      case LudoNoticeScene(:final kind, :final playerId):
        final who = playerId == me ? 'YOU' : name(playerId);
        return TurnBannerData(
          kind == LudoNoticeKind.thirdSix ? 'THREE SIXES — $who LOSE${playerId == me ? '' : 'S'} THE TURN' : 'NO MOVE FOR $who',
          find(playerId)?.color?.color ?? gold,
          mine: playerId == me,
        );
      case LudoExtraRollScene(:final playerId):
        return TurnBannerData(playerId == me ? 'EXTRA ROLL!' : '${name(playerId)} ROLLS AGAIN',
            find(playerId)?.color?.color ?? gold, mine: playerId == me);
      default:
        break;
    }
    return current == me ? TurnBannerData('YOUR TURN', color, mine: true) : TurnBannerData("${name(current)}'S TURN", color);
  }

  /// Standing hint under the board (empty while animations play).
  String get hint {
    if (timeline.isCatchingUp) return 'Catching up…';
    if (timeline.blocking || !drained || game.currentPlayerId != me || game.phase != LudoMatchPhase.playing) return '';
    return game.turnPhase == LudoTurnPhase.waitingForMove ? 'Tap a glowing token to move' : 'Tap your dice to roll';
  }

  /// Why a tap on the board did nothing; null when nothing needs saying.
  String? get tapExplanation {
    if (!online) return 'Reconnecting…';
    if (timeline.blocking || timeline.isCatchingUp || game.phase == LudoMatchPhase.finished) return null; // the hint returns right after
    if (game.phase == LudoMatchPhase.preGame) return 'Tap your dice to roll';
    if (game.currentPlayerId != me) return 'Wait for your turn';
    if (game.turnPhase == LudoTurnPhase.waitingForRoll) return 'Roll your dice first';
    return 'Tap a glowing token';
  }

  /// Participants with colors filled from the game state (any player count).
  static List<LudoMatchParticipant> withColors(List<LudoMatchParticipant> participants, LudoRuntimeSnapshot snapshot) {
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
}
