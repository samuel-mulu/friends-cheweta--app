import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/data/game_hub_repository.dart';
import 'package:friends_game_app/features/ludo/application/ludo_animation_queue.dart';
import 'package:friends_game_app/features/ludo/application/ludo_event_reducer.dart';
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
    this.sessionCode,
    this.legalMoves = const [],
    this.strikes = const {},
    this.maxStrikes = 3,
    this.autoPlayNotice,
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
  final String? sessionCode;

  /// Landing preview for the current move choice (cleared when the turn moves on).
  final List<LudoMovePreview> legalMoves;

  /// Consecutive timeouts per player ("away strikes"); forfeit at [maxStrikes].
  final Map<String, int> strikes;
  final int maxStrikes;
  final LudoAutoPlayNotice? autoPlayNotice;

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
    String? sessionCode,
    List<LudoMovePreview>? legalMoves,
    Map<String, int>? strikes,
    int? maxStrikes,
    LudoAutoPlayNotice? autoPlayNotice,
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
        sessionCode: sessionCode ?? this.sessionCode,
        legalMoves: legalMoves ?? this.legalMoves,
        strikes: strikes ?? this.strikes,
        maxStrikes: maxStrikes ?? this.maxStrikes,
        autoPlayNotice: autoPlayNotice ?? this.autoPlayNotice,
      );
}

class LudoMatchController extends Notifier<LudoMatchViewState> {
  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<GameSocketStatus>? _socketSub;
  int? _openEventVersion;
  final Set<String> _seenEventIds = <String>{};

  /// Events after which the previous landing preview no longer applies.
  static const _clearsPreview = {
    'ludo:dice_rolled',
    'ludo:token_moved',
    'ludo:turn_started',
    'ludo:extra_roll_granted',
    'ludo:no_legal_move',
    'match:finished',
  };
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

  /// Commands resolve to true when the server accepted them. State itself only
  /// changes from server events; the result lets the UI end optimistic effects.
  Future<bool> rollForStart() => _command('ludo:roll_for_start');
  Future<bool> roll() => _command('ludo:roll');
  Future<bool> resign() => _command('ludo:resign');
  Future<bool> move(String tokenId) => _command('ludo:move', tokenId: tokenId);

  Future<bool> _command(String eventName, {String? tokenId}) async {
    final snapshot = state.snapshot;
    final matchId = state.matchId;
    if (snapshot == null || matchId == null || state.pendingCommandId != null) return false;
    final commandId = _uuid.v4();
    state = state.copyWith(pendingCommandId: commandId, clearError: true);
    final payload = <String, dynamic>{
      'matchId': matchId,
      'commandId': commandId,
      'expectedVersion': snapshot.game.version,
      if (tokenId != null) 'tokenId': tokenId,
    };
    Map<String, dynamic> ack;
    try {
      ack = await ref.read(gameSocketServiceProvider).sendCommand(eventName, payload);
    } catch (_) {
      ack = const {'ok': false, 'code': 'SEND_FAILED'};
    }
    // Only clear our own command: a server event may already have cleared it.
    if (state.pendingCommandId == commandId) state = state.copyWith(clearPending: true);
    if (ack['ok'] == true) return true; // state itself changes only from server events
    state = state.copyWith(error: _ackMessage(ack));
    // Unknown outcome or stale view: ask the server for the truth instead of guessing.
    if (_recoverOn.contains(ack['code'])) unawaited(recover(reason: 'command_${ack['code']}'));
    return false;
  }

  /// Failures after which the local view may be wrong (the command may even
  /// have succeeded): resync from the server.
  static const _recoverOn = {'ACK_TIMEOUT', 'MATCH_VERSION_CONFLICT', 'SEND_FAILED', 'MATCH_ROOM_NOT_JOINED'};

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

    // Away strikes are not game-state versions; apply them directly.
    if (event.name == 'ludo:auto_played' || event.name == 'ludo:strikes') {
      final playerId = event.data['playerId']?.toString();
      if (playerId == null) return;
      final strikes = int.tryParse(event.data['strikes']?.toString() ?? '') ?? 0;
      final max = int.tryParse(event.data['maxStrikes']?.toString() ?? '') ?? state.maxStrikes;
      state = state.copyWith(
        strikes: {...state.strikes, playerId: strikes},
        maxStrikes: max,
        autoPlayNotice: event.name == 'ludo:auto_played'
            ? LudoAutoPlayNotice(playerId: playerId, strikes: strikes, maxStrikes: max, seq: (state.autoPlayNotice?.seq ?? 0) + 1)
            : null,
      );
      return;
    }

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

    final updated = reduceLudoEvent(snapshot, event, incoming);
    final timing = estimateTimingAfterEvent(state.timing, updated, event, turnSeconds: state.turnDurationSeconds);
    var lastDice = state.lastDiceByPlayer;
    if (event.name == 'ludo:starting_roll' || event.name == 'ludo:dice_rolled') {
      final rollerId = event.data['playerId']?.toString();
      final rolled = int.tryParse(event.data['diceValue']?.toString() ?? '');
      if (rollerId != null && rolled != null) {
        lastDice = {...lastDice, rollerId: rolled};
      }
    }
    state = state.copyWith(
      snapshot: updated,
      timing: timing,
      lastDiceByPlayer: lastDice,
      clearPending: true,
      clearError: true,
      legalMoves: event.name == 'ludo:legal_moves_ready'
          ? LudoMovePreview.listFrom(event.data['legalMoves'])
          : _clearsPreview.contains(event.name)
              ? const []
              : null,
    );
    _enqueuePresentation(event);
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
      case 'match:started':
        queue.enqueue(LudoPresentationEvent(kind: LudoPresentationKind.matchStarted, playerId: data['playerId']?.toString()));
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
      legalMoves: LudoMovePreview.listFrom(ack['legalMoves']),
      strikes: timing.consecutiveTimeoutsByPlayer,
      maxStrikes: state.maxStrikes,
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
      final sessionCode = json['sessionCode']?.toString();
      if (sessionCode != null && sessionCode.isNotEmpty) {
        state = state.copyWith(sessionCode: sessionCode);
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
      case 'SOCKET_DISCONNECTED':
        return 'Reconnecting… your move was not sent.';
      case 'ACK_TIMEOUT':
      case 'SEND_FAILED':
        return 'Slow connection. Syncing the board…';
      default:
        return ack['message']?.toString() ?? 'The game request failed.';
    }
  }
}

final ludoMatchControllerProvider = NotifierProvider<LudoMatchController, LudoMatchViewState>(LudoMatchController.new);
