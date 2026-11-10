import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/dama/application/dama_event_reducer.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/game_hub/data/game_hub_repository.dart';

/// "The server played for X" notice (seq increases so the UI shows it once).
class DamaAutoPlayNotice {
  const DamaAutoPlayNotice({required this.playerId, required this.strikes, required this.maxStrikes, required this.seq});
  final String playerId;
  final int strikes;
  final int maxStrikes;
  final int seq;
}

class DamaMatchViewState {
  const DamaMatchViewState({
    this.matchId,
    this.game,
    this.timing = const DamaTiming(),
    this.participants = const [],
    this.legalMoves = const [],
    this.loading = false,
    this.recovering = false,
    this.pendingCommandId,
    this.error,
    this.cancelledReason,
    this.sessionCode,
    this.turnSeconds = 40,
    this.autoPlayNotice,
  });

  final String? matchId;
  final DamaGame? game;
  final DamaTiming timing;
  final List<DamaParticipant> participants;

  /// What the player to move may play (from the server).
  final List<DamaMove> legalMoves;
  final bool loading;
  final bool recovering;
  final String? pendingCommandId;
  final String? error;
  final String? cancelledReason;
  final String? sessionCode;
  final int turnSeconds;
  final DamaAutoPlayNotice? autoPlayNotice;

  DamaParticipant? participant(String? userId) {
    for (final p in participants) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  DamaMatchViewState copyWith({
    DamaGame? game,
    DamaTiming? timing,
    List<DamaParticipant>? participants,
    List<DamaMove>? legalMoves,
    bool? loading,
    bool? recovering,
    String? pendingCommandId,
    bool clearPending = false,
    String? error,
    bool clearError = false,
    String? cancelledReason,
    String? sessionCode,
    int? turnSeconds,
    DamaAutoPlayNotice? autoPlayNotice,
  }) =>
      DamaMatchViewState(
        matchId: matchId,
        game: game ?? this.game,
        timing: timing ?? this.timing,
        participants: participants ?? this.participants,
        legalMoves: legalMoves ?? this.legalMoves,
        loading: loading ?? this.loading,
        recovering: recovering ?? this.recovering,
        pendingCommandId: clearPending ? null : pendingCommandId ?? this.pendingCommandId,
        error: clearError ? null : error ?? this.error,
        cancelledReason: cancelledReason ?? this.cancelledReason,
        sessionCode: sessionCode ?? this.sessionCode,
        turnSeconds: turnSeconds ?? this.turnSeconds,
        autoPlayNotice: autoPlayNotice ?? this.autoPlayNotice,
      );
}

/// Live Dama match: joins, applies server events in version order, sends
/// moves. State changes only from the server; commands fail fast and resync
/// when their outcome is unknown.
class DamaMatchController extends Notifier<DamaMatchViewState> {
  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<GameSocketStatus>? _socketSub;
  int? _openVersion;
  final Set<String> _seenEventIds = {};
  static const _uuid = Uuid();

  @override
  DamaMatchViewState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    _eventSub?.cancel();
    _socketSub?.cancel();
    _eventSub = socket.events.listen(_onEvent);
    _socketSub = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected && state.game != null) unawaited(recover());
    });
    ref.onDispose(() {
      _eventSub?.cancel();
      _socketSub?.cancel();
    });
    return const DamaMatchViewState();
  }

  Future<void> join(String matchId) async {
    if (matchId.isEmpty || (state.matchId == matchId && state.game != null)) return;
    state = DamaMatchViewState(matchId: matchId, loading: true);
    _openVersion = null;
    _seenEventIds.clear();
    try {
      final socket = ref.read(gameSocketServiceProvider);
      await socket.connect();
      _applySnapshot(await socket.emitWithAck('dama:join', {'matchId': matchId}));
      unawaited(_loadMatchInfo(matchId));
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not join this match. Check your connection and try again.');
    }
  }

  /// Re-join the room (membership is per connection) and take the server's state.
  Future<void> recover() async {
    final matchId = state.matchId;
    if (matchId == null || state.recovering) return;
    state = state.copyWith(recovering: true, clearError: true);
    try {
      final socket = ref.read(gameSocketServiceProvider);
      if (!socket.isConnected) await socket.connect();
      _applySnapshot(await socket.emitWithAck('dama:join', {'matchId': matchId}));
    } catch (_) {
      state = state.copyWith(recovering: false, error: 'Connection restored, but match recovery is still pending.');
    }
  }

  Future<bool> move(DamaMove move) => _command('dama:move', {'path': move.path});
  Future<bool> resign() => _command('dama:resign', const {});

  Future<bool> _command(String event, Map<String, dynamic> extra) async {
    final game = state.game;
    final matchId = state.matchId;
    if (game == null || matchId == null || state.pendingCommandId != null) return false;
    final commandId = _uuid.v4();
    state = state.copyWith(pendingCommandId: commandId, clearError: true);
    Map<String, dynamic> ack;
    try {
      ack = await ref.read(gameSocketServiceProvider).sendCommand(event, {
        'matchId': matchId,
        'commandId': commandId,
        'expectedVersion': game.version,
        ...extra,
      });
    } catch (_) {
      ack = const {'ok': false, 'code': 'SEND_FAILED'};
    }
    if (state.pendingCommandId == commandId) state = state.copyWith(clearPending: true);
    if (ack['ok'] == true) return true;
    state = state.copyWith(error: damaErrorMessage(ack));
    if (_recoverOn.contains(ack['code'])) unawaited(recover());
    return false;
  }

  static const _recoverOn = {'ACK_TIMEOUT', 'MATCH_VERSION_CONFLICT', 'SEND_FAILED', 'MATCH_ROOM_NOT_JOINED', 'ILLEGAL_DAMA_MOVE'};

  void _onEvent(RealtimeEvent event) {
    final game = state.game;
    if (game == null || event.matchId != state.matchId) return;
    if (!event.name.startsWith('dama:') && !event.name.startsWith('match:')) return;
    if (event.name == 'match:cancelled') {
      state = state.copyWith(
        cancelledReason: event.data['reason']?.toString() ?? 'MATCH_CANCELLED',
        clearPending: true,
        error: 'Match cancelled. Reserved entry funds are handled by the server.',
      );
      return;
    }
    if (event.eventId != null && !_seenEventIds.add(event.eventId!)) return;

    if (event.name == 'dama:auto_played' || event.name == 'dama:strikes') {
      final playerId = event.data['playerId']?.toString();
      if (playerId == null) return;
      final strikes = int.tryParse(event.data['strikes']?.toString() ?? '') ?? 0;
      final max = int.tryParse(event.data['maxStrikes']?.toString() ?? '') ?? state.timing.maxStrikes;
      state = state.copyWith(
        timing: DamaTiming(
          version: state.timing.version,
          playerId: state.timing.playerId,
          turnEndsAt: state.timing.turnEndsAt,
          strikes: {...state.timing.strikes, playerId: strikes},
          maxStrikes: max,
        ),
        autoPlayNotice: event.name == 'dama:auto_played'
            ? DamaAutoPlayNotice(playerId: playerId, strikes: strikes, maxStrikes: max, seq: (state.autoPlayNotice?.seq ?? 0) + 1)
            : null,
      );
      return;
    }
    if (event.name.startsWith('match:') && event.name != 'match:finished') return; // chat, reactions…

    // One command's events share a version: accept the first event of
    // version+1 and the rest of that same version; resync on any gap.
    final incoming = event.version;
    if (incoming == null || incoming < game.version) return;
    if (incoming == game.version && _openVersion != incoming) return;
    if (incoming > game.version + 1) {
      _openVersion = null;
      unawaited(recover());
      return;
    }
    _openVersion = incoming;

    final next = reduceDamaEvent(game, event, incoming);
    final legal = switch (event.name) {
      'dama:turn_started' => DamaMove.listFrom(event.data['legalMoves']),
      'dama:piece_moved' || 'match:finished' => const <DamaMove>[],
      _ => null,
    };
    // The clock restarts with each turn (the exact deadline arrives with the next sync).
    final timing = event.name == 'dama:turn_started'
        ? DamaTiming(
            version: incoming,
            playerId: next.currentPlayerId,
            turnEndsAt: DateTime.now().add(Duration(seconds: state.turnSeconds)),
            strikes: state.timing.strikes,
            maxStrikes: state.timing.maxStrikes,
          )
        : next.finished
            ? DamaTiming(version: incoming, strikes: state.timing.strikes, maxStrikes: state.timing.maxStrikes)
            : null;
    state = state.copyWith(game: next, legalMoves: legal, timing: timing, clearPending: true, clearError: true);
  }

  void _applySnapshot(Map<String, dynamic> ack) {
    if (ack['ok'] != true || ack['state'] is! Map) {
      state = state.copyWith(loading: false, recovering: false, error: damaErrorMessage(ack));
      return;
    }
    final raw = Map<String, dynamic>.from(ack['state'] as Map);
    final game = DamaGame.fromJson(Map<String, dynamic>.from(raw['game'] as Map? ?? const {}));
    _openVersion = null;
    state = state.copyWith(
      game: game,
      timing: ack['timing'] is Map ? DamaTiming.fromJson(Map<String, dynamic>.from(ack['timing'] as Map)) : state.timing,
      participants: (ack['participants'] as List? ?? const [])
          .whereType<Map>()
          .map((p) => DamaParticipant.fromJson(Map<String, dynamic>.from(p)))
          .toList(),
      legalMoves: DamaMove.listFrom(ack['legalMoves']),
      loading: false,
      recovering: false,
      clearPending: true,
      clearError: true,
    );
  }

  /// Move time and session code (display only; failures are harmless).
  Future<void> _loadMatchInfo(String matchId) async {
    try {
      final json = await ref.read(gameHubRepositoryProvider).getMatch(matchId);
      final mode = json['gameMode'];
      final seconds = mode is Map ? int.tryParse(mode['turnDurationSeconds']?.toString() ?? '') : null;
      state = state.copyWith(
        turnSeconds: seconds != null && seconds > 0 ? seconds : null,
        sessionCode: json['sessionCode']?.toString(),
      );
    } catch (_) {}
  }
}

String damaErrorMessage(Map<String, dynamic> ack) => switch (ack['code']?.toString()) {
      'NOT_PLAYER_TURN' => 'It is not your turn.',
      'ILLEGAL_DAMA_MOVE' => 'That move is not allowed. Syncing the board…',
      'MATCH_VERSION_CONFLICT' => 'The board changed. Syncing…',
      'MATCH_ROOM_NOT_JOINED' => 'Rejoining the match room…',
      'MATCH_NOT_PLAYING' => 'This match has ended.',
      'MATCH_NOT_ACTIVE' => 'This match is no longer active.',
      'SOCKET_DISCONNECTED' => 'Reconnecting… your move was not sent.',
      'ACK_TIMEOUT' || 'SEND_FAILED' => 'Slow connection. Syncing the board…',
      _ => ack['message']?.toString() ?? 'The game request failed.',
    };

final damaMatchControllerProvider = NotifierProvider<DamaMatchController, DamaMatchViewState>(DamaMatchController.new);
