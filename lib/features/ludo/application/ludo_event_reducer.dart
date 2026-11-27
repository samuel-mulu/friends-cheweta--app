import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';

// Pure functions that apply one server event to the local snapshot. The
// server stays authoritative: a version gap triggers a full resync instead.

/// The snapshot after [event] (already known to be the next [version]).
LudoRuntimeSnapshot reduceLudoEvent(LudoRuntimeSnapshot snapshot, RealtimeEvent event, int version) {
  var game = snapshot.game.copyWith(version: version);
  var startingRoll = snapshot.startingRoll;
  final resigned = [...snapshot.resignedPlayerIds];
  final missed = [...snapshot.missedCapturePlayerIds];
  final data = event.data;
  final playerId = data['playerId']?.toString();

  switch (event.name) {
    case 'ludo:starting_roll':
      final value = int.tryParse(data['diceValue']?.toString() ?? '') ?? 0;
      if (playerId != null) startingRoll = startingRoll.copyWith(rolls: {...startingRoll.rolls, playerId: value});
      break;
    case 'ludo:starting_roll_tie':
      startingRoll = startingRoll.copyWith(
        round: int.tryParse(data['round']?.toString() ?? '') ?? startingRoll.round,
        candidatePlayerIds: (data['candidatePlayerIds'] as List? ?? const []).map((e) => e.toString()).toList(),
        rolls: {},
      );
      break;
    case 'match:started':
      game = game.copyWith(
        phase: LudoMatchPhase.playing,
        turnPhase: LudoTurnPhase.waitingForRoll,
        currentPlayerId: playerId,
        clearDiceValue: true,
        legalTokenIds: const [],
        consecutiveSixes: 0,
      );
      break;
    case 'ludo:turn_started':
      game = game.copyWith(
        phase: LudoMatchPhase.playing,
        turnPhase: LudoTurnPhase.waitingForRoll,
        currentPlayerId: playerId,
        clearDiceValue: true,
        legalTokenIds: const [],
        consecutiveSixes: 0,
      );
      break;
    case 'ludo:dice_rolled':
      final dice = int.tryParse(data['diceValue']?.toString() ?? '');
      final sixes = dice == 6 ? game.consecutiveSixes + 1 : 0;
      game = game.copyWith(diceValue: dice, consecutiveSixes: sixes.clamp(0, 2).toInt(), legalTokenIds: const []);
      break;
    case 'ludo:legal_moves_ready':
      game = game.copyWith(
        turnPhase: LudoTurnPhase.waitingForMove,
        legalTokenIds: (data['tokenIds'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
      break;
    case 'ludo:third_six_forfeited':
      game = game.copyWith(consecutiveSixes: 0);
      break;
    case 'ludo:token_moved':
      final rawMove = data['move'];
      if (rawMove is Map) {
        final resolution = LudoMoveResolution.fromJson(Map<String, dynamic>.from(rawMove));
        game = _applyMove(game, resolution, includeCaptures: true);
      }
      game = game.copyWith(clearDiceValue: true, legalTokenIds: const []);
      break;
    case 'ludo:extra_roll_granted':
      game = game.copyWith(
        turnPhase: LudoTurnPhase.waitingForRoll,
        currentPlayerId: playerId,
        clearDiceValue: true,
        legalTokenIds: const [],
      );
      break;
    case 'ludo:player_finished':
      if (playerId != null && !game.winnerOrder.contains(playerId)) {
        game = game.copyWith(winnerOrder: [...game.winnerOrder, playerId]);
      }
      game = _retire(game, data['tokenIds']);
      break;
    case 'ludo:player_resigned':
    // "Forget to send back and you lose": out like a resignation.
    case 'ludo:capture_missed':
      if (playerId != null && !resigned.contains(playerId)) resigned.add(playerId);
      if (event.name == 'ludo:capture_missed' && playerId != null && !missed.contains(playerId)) missed.add(playerId);
      game = _retire(game, data['tokenIds']);
      break;
    case 'match:finished':
      game = game.copyWith(
        phase: LudoMatchPhase.finished,
        turnPhase: LudoTurnPhase.complete,
        clearCurrentPlayer: true,
        clearDiceValue: true,
        legalTokenIds: const [],
        consecutiveSixes: 0,
        winnerOrder: (data['winnerOrder'] as List? ?? game.winnerOrder).map((e) => e.toString()).toList(),
      );
      break;
  }
  return snapshot.copyWith(game: game, startingRoll: startingRoll, resignedPlayerIds: resigned, missedCapturePlayerIds: missed);
}

/// Presented-board step for a walk that just ended: the mover lands. Captured
/// tokens go home here only when no capture scene follows ([includeCaptures]).
LudoRuntimeSnapshot applyMoveToPresented(
  LudoRuntimeSnapshot snapshot,
  RealtimeEvent event,
  LudoMoveResolution move, {
  required bool includeCaptures,
}) {
  var game = snapshot.game.copyWith(version: event.version ?? snapshot.game.version);
  game = _applyMove(game, move, includeCaptures: includeCaptures);
  game = game.copyWith(clearDiceValue: true, legalTokenIds: const []);
  return snapshot.copyWith(game: game);
}

/// Presented-board step for a capture flight that just landed in the yard.
LudoRuntimeSnapshot applyCapturesToPresented(LudoRuntimeSnapshot snapshot, Iterable<String> capturedTokenIds) {
  var game = snapshot.game;
  for (final capturedId in capturedTokenIds) {
    final captured = game.tokenById(capturedId);
    if (captured != null) game = game.replaceToken(captured.copyWith(state: LudoTokenState.base, progress: -1));
  }
  return snapshot.copyWith(game: game);
}

LudoGameState _applyMove(LudoGameState game, LudoMoveResolution resolution, {required bool includeCaptures}) {
  game = game.replaceToken(resolution.tokenAfter);
  if (!includeCaptures) return game;
  for (final capturedId in resolution.capturedTokenIds) {
    final captured = game.tokenById(capturedId);
    if (captured != null) game = game.replaceToken(captured.copyWith(state: LudoTokenState.base, progress: -1));
  }
  return game;
}

/// A player who is out takes their shared-track tokens back to the yard (the
/// server lists exactly which ones; home-lane tokens stay where they are).
LudoGameState _retire(LudoGameState game, Object? tokenIds) {
  for (final id in (tokenIds as List? ?? const []).map((e) => e.toString())) {
    final token = game.tokenById(id);
    if (token != null) game = game.replaceToken(token.copyWith(state: LudoTokenState.base, progress: -1));
  }
  return game;
}

/// Turn deadline estimate until the next exact timing arrives from the server.
LudoTimingState? estimateTimingAfterEvent(
  LudoTimingState? current,
  LudoRuntimeSnapshot snapshot,
  RealtimeEvent event, {
  required int turnSeconds,
}) {
  if (snapshot.game.phase == LudoMatchPhase.finished || snapshot.game.turnPhase == LudoTurnPhase.complete) {
    return current?.copyWith(
      version: snapshot.game.version,
      clearPlayer: true,
      turnPhase: snapshot.game.turnPhase,
      clearDeadline: true,
      estimated: false,
    );
  }
  final changesDeadline = const {
    'ludo:starting_roll',
    'ludo:starting_roll_tie',
    'match:started',
    'ludo:turn_started',
    'ludo:legal_moves_ready',
    'ludo:extra_roll_granted',
  }.contains(event.name);
  if (!changesDeadline) return current?.copyWith(version: snapshot.game.version);
  final serverTime = event.serverTime;
  final deadline = serverTime?.add(Duration(seconds: turnSeconds));
  if (current == null) {
    return LudoTimingState(
      matchId: snapshot.game.matchId,
      version: snapshot.game.version,
      playerId: snapshot.game.currentPlayerId,
      turnPhase: snapshot.game.turnPhase,
      turnEndsAt: deadline,
      consecutiveTimeoutsByPlayer: const {},
      estimated: true,
    );
  }
  return current.copyWith(
    version: snapshot.game.version,
    playerId: snapshot.game.currentPlayerId,
    turnPhase: snapshot.game.turnPhase,
    turnEndsAt: deadline,
    clearDeadline: deadline == null,
    estimated: true,
  );
}
