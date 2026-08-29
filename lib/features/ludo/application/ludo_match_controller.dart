import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/data/game_hub_repository.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';

class LudoMatchViewState {
  const LudoMatchViewState({
    this.matchId,
    this.snapshot,
    this.timing,
    this.participants = const [],
    this.lastDiceByPlayer = const {},
    this.loading = false,
    this.recovering = false,
    this.pendingCommandId,
    this.error,
    this.turnDurationSeconds = 30,
    this.cancelledReason,
  });

  final String? matchId;
  final LudoRuntimeSnapshot? snapshot;
  final LudoTimingState? timing;
  final List<LudoMatchParticipant> participants;
  final Map<String, int> lastDiceByPlayer;
  final bool loading;
  final bool recovering;
  final String? pendingCommandId;
  final String? error;
  final int turnDurationSeconds;
  final String? cancelledReason;

  int get version => snapshot?.game.version ?? -1;
  bool get ready => snapshot != null;

  LudoMatchViewState copyWith({
    String? matchId,
    LudoRuntimeSnapshot? snapshot,
    LudoTimingState? timing,
    List<LudoMatchParticipant>? participants,
    Map<String, int>? lastDiceByPlayer,
    bool? loading,
    bool? recovering,
    String? pendingCommandId,
    bool clearPending = false,
    String? error,
    bool clearError = false,
    int? turnDurationSeconds,
    String? cancelledReason,
  }) =>
      LudoMatchViewState(
        matchId: matchId ?? this.matchId,
        snapshot: snapshot ?? this.snapshot,
        timing: timing ?? this.timing,
        participants: participants ?? this.participants,
        lastDiceByPlayer: lastDiceByPlayer ?? this.lastDiceByPlayer,
        loading: loading ?? this.loading,
        recovering: recovering ?? this.recovering,
        pendingCommandId: clearPending ? null : pendingCommandId ?? this.pendingCommandId,
        error: clearError ? null : error ?? this.error,
        turnDurationSeconds: turnDurationSeconds ?? this.turnDurationSeconds,
        cancelledReason: cancelledReason ?? this.cancelledReason,
      );
}

class LudoMatchController extends Notifier<LudoMatchViewState> {
  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<GameSocketStatus>? _socketSub;
  int? _openEventVersion;
  final Set<String> _seenEventIds = <String>{};
  final Uuid _uuid = const Uuid();

  @override
  LudoMatchViewState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    _eventSub?.cancel();
    _socketSub?.cancel();
    _eventSub = socket.events.listen(_onEvent);
    _socketSub = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected && state.matchId != null && state.snapshot != null) {
        unawaited(recover(reason: 'socket_reconnected'));
      }
    });
    ref.onDispose(() {
      _eventSub?.cancel();
      _socketSub?.cancel();
    });
    return const LudoMatchViewState();
  }

  Future<void> join(String matchId) async {
    if (matchId.isEmpty) return;
    if (state.matchId == matchId && state.snapshot != null) return;
    state = LudoMatchViewState(matchId: matchId, loading: true, turnDurationSeconds: state.turnDurationSeconds);
    _openEventVersion = null;
    _seenEventIds.clear();
    ref.read(ludoAnimationQueueProvider.notifier).clear();
    try {
      final socket = ref.read(gameSocketServiceProvider);
      await socket.connect();
      final ack = await socket.emitWithAck('match:join', {'matchId': matchId});
      _applySnapshotAck(ack, matchId: matchId);
      await _loadTurnDuration(matchId);
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not join this match. Check your connection and try again.');
    }
  }

  Future<void> recover({String reason = 'manual_recovery'}) async {
    final matchId = state.matchId;
    if (matchId == null || state.recovering) return;
    state = state.copyWith(recovering: true, clearError: true);
    try {
      final socket = ref.read(gameSocketServiceProvider);
      if (!socket.isConnected) await socket.connect();
      // Rejoin first: room membership is connection-specific.
      final joinAck = await socket.emitWithAck('match:join', {'matchId': matchId});
      if (joinAck['ok'] != true) {
        state = state.copyWith(recovering: false, error: _ackMessage(joinAck));
        return;
      }
      final syncAck = await socket.emitWithAck('ludo:sync', {'matchId': matchId});
      _applySnapshotAck(syncAck, matchId: matchId, recovering: false);
    } catch (_) {
      state = state.copyWith(recovering: false, error: 'Connection restored, but match recovery is still pending.');
    }
  }

  Future<void> rollForStart() => _command('ludo:roll_for_start');
  Future<void> roll() => _command('ludo:roll');
  Future<void> resign() => _command('ludo:resign');
  Future<void> move(String tokenId) => _command('ludo:move', tokenId: tokenId);

  Future<void> _command(String eventName, {String? tokenId}) async {
    final snapshot = state.snapshot;
    final matchId = state.matchId;
    if (snapshot == null || matchId == null || state.pendingCommandId != null) return;
    final commandId = _uuid.v4();
    state = state.copyWith(pendingCommandId: commandId, clearError: true);
    final payload = <String, dynamic>{
      'matchId': matchId,
      'commandId': commandId,
      'expectedVersion': snapshot.game.version,
      if (tokenId != null) 'tokenId': tokenId,
    };
    try {
      var ack = await ref.read(gameSocketServiceProvider).emitWithAck(eventName, payload);
      if (ack['ok'] != true && ack['code'] == 'ACK_TIMEOUT') {
        // Same user action, same commandId. Backend Redis dedupe makes retry safe.
        ack = await ref.read(gameSocketServiceProvider).emitWithAck(eventName, payload);
      }
      if (ack['ok'] == true) {
        state = state.copyWith(clearPending: true);
        return; // ACK means accepted/deduped. State changes only from server EVENT.
      }
      state = state.copyWith(clearPending: true, error: _ackMessage(ack));
      if (ack['code'] == 'MATCH_VERSION_CONFLICT') unawaited(recover(reason: 'version_conflict'));
    } catch (_) {
      state = state.copyWith(clearPending: true, error: 'The command could not be sent. Reconnect and try again.');
    }
  }

  void _onEvent(RealtimeEvent event) {
    final matchId = state.matchId;
    final snapshot = state.snapshot;
    if (matchId == null || snapshot == null || event.matchId != matchId) return;
    if (!event.name.startsWith('ludo:') && !event.name.startsWith('match:')) return;
    if (event.protocolVersion != null && event.protocolVersion != 1) {
      state = state.copyWith(error: 'Realtime protocol changed. Recovering the latest match snapshot…');
      unawaited(recover(reason: 'protocol_mismatch'));
      return;
    }
    if (event.name == 'match:cancelled') {
      final reason = event.data['reason']?.toString() ?? 'MATCH_CANCELLED';
      state = state.copyWith(cancelledReason: reason, clearPending: true, error: 'Match cancelled. Reserved entry funds are handled by the server.');
      return;
    }
    if (event.eventId != null && !_seenEventIds.add(event.eventId!)) return;

    final incoming = event.version;
    if (incoming == null) return;
    final current = snapshot.game.version;
    if (incoming < current) return;
    if (incoming == current && _openEventVersion != incoming) return;
    if (incoming > current + 1) {
      _openEventVersion = null;
      unawaited(recover(reason: 'version_gap'));
      return;
    }
    if (incoming == current + 1) _openEventVersion = incoming;

    final updated = _reduce(snapshot, event, incoming);
    final timing = _estimatedTimingAfterEvent(updated, event);
    var lastDice = state.lastDiceByPlayer;
    if (event.name == 'ludo:starting_roll' || event.name == 'ludo:dice_rolled') {
      final rollerId = event.data['playerId']?.toString();
      final rolled = int.tryParse(event.data['diceValue']?.toString() ?? '');
      if (rollerId != null && rolled != null) {
        lastDice = {...lastDice, rollerId: rolled};
      }
    }
    state = state.copyWith(snapshot: updated, timing: timing, lastDiceByPlayer: lastDice, clearPending: true, clearError: true);
    _enqueuePresentation(event);
  }

  LudoRuntimeSnapshot _reduce(LudoRuntimeSnapshot snapshot, RealtimeEvent event, int version) {
    var game = snapshot.game.copyWith(version: version);
    var startingRoll = snapshot.startingRoll;
    final resigned = [...snapshot.resignedPlayerIds];
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
          game = game.replaceToken(resolution.tokenAfter);
          for (final capturedId in resolution.capturedTokenIds) {
            final captured = game.tokenById(capturedId);
            if (captured != null) game = game.replaceToken(captured.copyWith(state: LudoTokenState.base, progress: -1));
          }
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
        break;
      case 'ludo:player_resigned':
        if (playerId != null && !resigned.contains(playerId)) resigned.add(playerId);
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
    return snapshot.copyWith(game: game, startingRoll: startingRoll, resignedPlayerIds: resigned);
  }

  LudoTimingState? _estimatedTimingAfterEvent(LudoRuntimeSnapshot snapshot, RealtimeEvent event) {
    final current = state.timing;
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
    final deadline = serverTime?.add(Duration(seconds: state.turnDurationSeconds));
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

  void _enqueuePresentation(RealtimeEvent event) {
    final queue = ref.read(ludoAnimationQueueProvider.notifier);
    final data = event.data;
    switch (event.name) {
      case 'ludo:starting_roll':
      case 'ludo:dice_rolled':
        queue.enqueue(LudoPresentationEvent(
          kind: LudoPresentationKind.dice,
          playerId: data['playerId']?.toString(),
          diceValue: int.tryParse(data['diceValue']?.toString() ?? ''),
        ));
        break;
      case 'ludo:token_moved':
        final raw = data['move'];
        if (raw is Map) {
          final move = LudoMoveResolution.fromJson(Map<String, dynamic>.from(raw));
          queue.enqueue(LudoPresentationEvent(kind: LudoPresentationKind.move, playerId: move.playerId, tokenId: move.tokenAfter.id, move: move));
        }
        break;
      case 'ludo:token_captured':
        queue.enqueue(LudoPresentationEvent(
          kind: LudoPresentationKind.capture,
          playerId: data['playerId']?.toString(),
          tokenId: data['tokenId']?.toString(),
          tokenIds: (data['tokenIds'] as List? ?? const []).map((e) => e.toString()).toList(),
        ));
        break;
      case 'ludo:token_finished':
        queue.enqueue(LudoPresentationEvent(kind: LudoPresentationKind.finish, playerId: data['playerId']?.toString(), tokenId: data['tokenId']?.toString()));
        break;
      case 'ludo:turn_started':
        queue.enqueue(LudoPresentationEvent(kind: LudoPresentationKind.turn, playerId: data['playerId']?.toString()));
        break;
      case 'ludo:extra_roll_granted':
        queue.enqueue(LudoPresentationEvent(kind: LudoPresentationKind.extraRoll, playerId: data['playerId']?.toString()));
        break;
      case 'match:finished':
        queue.enqueue(const LudoPresentationEvent(kind: LudoPresentationKind.matchFinished));
        break;
    }
  }

  void _applySnapshotAck(Map<String, dynamic> ack, {required String matchId, bool recovering = false}) {
    if (ack['ok'] != true) {
      state = state.copyWith(loading: false, recovering: false, error: _ackMessage(ack));
      return;
    }
    final rawState = ack['state'];
    final rawTiming = ack['timing'];
    if (rawState is! Map || rawTiming is! Map) {
      state = state.copyWith(loading: false, recovering: false, error: 'The server returned an invalid match snapshot.');
      return;
    }
    final snapshot = LudoRuntimeSnapshot.fromJson(Map<String, dynamic>.from(rawState));
    final timing = LudoTimingState.fromJson(Map<String, dynamic>.from(rawTiming));
    final participants = _parseParticipants(ack['participants'], snapshot);
    final lastDice = _seedDiceHistory(snapshot);
    _openEventVersion = null; // delayed events at this snapshot version are ignored safely.
    state = LudoMatchViewState(
      matchId: matchId,
      snapshot: snapshot,
      timing: timing,
      participants: participants,
      lastDiceByPlayer: lastDice,
      loading: false,
      recovering: recovering,
      turnDurationSeconds: state.turnDurationSeconds,
    );
  }

  Map<String, int> _seedDiceHistory(LudoRuntimeSnapshot snapshot) {
    final history = Map<String, int>.from(snapshot.startingRoll.rolls);
    final roller = snapshot.game.currentPlayerId;
    final dice = snapshot.game.diceValue;
    if (roller != null && dice != null) history[roller] = dice;
    return history;
  }

  List<LudoMatchParticipant> _parseParticipants(Object? raw, LudoRuntimeSnapshot snapshot) {
    final colorByUserId = {
      for (final player in snapshot.game.players) player.userId: player.color,
    };

    List<LudoMatchParticipant> parsed;
    if (raw is List && raw.isNotEmpty) {
      parsed = raw
          .whereType<Map>()
          .map((item) => LudoMatchParticipant.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } else {
      parsed = snapshot.game.players
          .map((player) => LudoMatchParticipant(userId: player.userId, fullName: 'Player', seat: 0, color: player.color))
          .toList(growable: false);
    }

    return parsed
        .map((participant) => LudoMatchParticipant(
              userId: participant.userId,
              fullName: participant.fullName,
              seat: participant.seat,
              color: participant.color ?? colorByUserId[participant.userId],
            ))
        .toList(growable: false);
  }

  Future<void> _loadTurnDuration(String matchId) async {
    try {
      final json = await ref.read(gameHubRepositoryProvider).getMatch(matchId);
      final rawMode = json['gameMode'];
      if (rawMode is Map) {
        final seconds = int.tryParse(rawMode['turnDurationSeconds']?.toString() ?? '');
        if (seconds != null && seconds > 0) state = state.copyWith(turnDurationSeconds: seconds);
      }
      final rawParticipants = json['participants'];
      if (rawParticipants is List && rawParticipants.isNotEmpty && state.participants.isEmpty) {
        final participants = rawParticipants
            .whereType<Map>()
            .map((item) => LudoMatchParticipant.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false);
        state = state.copyWith(participants: participants);
      }
    } catch (_) {
      // Timer display can still use the exact current deadline from join/sync.
    }
  }

  bool get isMyTurn {
    final userId = ref.read(authControllerProvider).user?.id;
    return userId != null && state.snapshot?.game.currentPlayerId == userId;
  }

  String _ackMessage(Map<String, dynamic> ack) {
    switch (ack['code']?.toString()) {
      case 'WAITING_FOR_OPPONENT_JOIN':
        return 'Waiting for your opponent to join the match.';
      case 'MATCH_VERSION_CONFLICT':
        return 'Your game state was behind the server. Recovering the match…';
      case 'NOT_PLAYER_TURN':
        return 'It is not your turn.';
      case 'INVALID_TURN_PHASE':
        return 'That action is not available right now.';
      case 'ILLEGAL_LUDO_MOVE':
        return 'That token cannot move with this roll.';
      case 'MATCH_ROOM_NOT_JOINED':
        return 'Rejoining the match room…';
      case 'MATCH_NOT_ACTIVE':
        return 'This match is no longer active.';
      default:
        return ack['message']?.toString() ?? 'The game request failed.';
    }
  }
}

final ludoMatchControllerProvider = NotifierProvider<LudoMatchController, LudoMatchViewState>(LudoMatchController.new);
