import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/matchmaking/domain/match_summary.dart';
import 'package:friends_game_app/features/matchmaking/domain/matchmaking_phase.dart';
import 'package:friends_game_app/features/matchmaking/domain/ready_player.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

class MatchmakingState {
  const MatchmakingState({
    this.phase = MatchmakingPhase.browsing,
    this.gameModeId,
    this.ticketId,
    this.matchId,
    this.match,
    this.readyPlayers = const [],
    this.busy = false,
    this.error,
  });

  final MatchmakingPhase phase;
  final String? gameModeId;
  final String? ticketId;
  final String? matchId;
  final MatchSummary? match;
  final List<ReadyPlayer> readyPlayers;
  final bool busy;
  final String? error;

  bool get isReady => phase == MatchmakingPhase.waitingInLobby || phase == MatchmakingPhase.pairing;
  bool get isMatched => phase == MatchmakingPhase.matchFound || phase == MatchmakingPhase.enteringMatch;
  bool get showMatchFound => phase == MatchmakingPhase.matchFound && match != null;
  int get readyCount => readyPlayers.length;

  MatchmakingState copyWith({
    MatchmakingPhase? phase,
    String? gameModeId,
    String? ticketId,
    String? matchId,
    MatchSummary? match,
    List<ReadyPlayer>? readyPlayers,
    bool? busy,
    String? error,
    bool clearError = false,
    bool clearMatch = false,
  }) {
    return MatchmakingState(
      phase: phase ?? this.phase,
      gameModeId: gameModeId ?? this.gameModeId,
      ticketId: ticketId ?? this.ticketId,
      matchId: matchId ?? this.matchId,
      match: clearMatch ? null : match ?? this.match,
      readyPlayers: readyPlayers ?? this.readyPlayers,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class MatchmakingController extends Notifier<MatchmakingState> {
  StreamSubscription<RealtimeEvent>? _eventSubscription;
  StreamSubscription<GameSocketStatus>? _statusSubscription;
  Timer? _lobbyRefreshTimer;
  String? _subscribedModeId;

  @override
  MatchmakingState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    _eventSubscription?.cancel();
    _statusSubscription?.cancel();
    _lobbyRefreshTimer?.cancel();
    _eventSubscription = socket.events.listen(_onRealtimeEvent);
    _statusSubscription = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected && !state.isMatched) {
        unawaited(recover());
      }
    });
    ref.onDispose(() {
      _eventSubscription?.cancel();
      _statusSubscription?.cancel();
      _lobbyRefreshTimer?.cancel();
      unawaited(_unsubscribeLobby());
    });
    return const MatchmakingState();
  }

  Future<void> openLobby(String gameModeId) async {
    state = state.copyWith(gameModeId: gameModeId, phase: MatchmakingPhase.browsing, clearError: true);
    await _subscribeLobby(gameModeId);
    _startLobbyRefresh(gameModeId);
    await recover();
    if (state.isMatched) return;
    await refreshLobby(gameModeId);
  }

  Future<void> goReady(String gameModeId) async {
    if (state.busy || state.isMatched || state.isReady) return;
    state = state.copyWith(busy: true, clearError: true, clearMatch: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck(
        'matchmaking:join',
        {'gameModeId': gameModeId},
      );
      _applyAck(ack, fallbackModeId: gameModeId);
      unawaited(ref.read(walletControllerProvider.notifier).refresh());
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Could not mark you as ready.');
    }
  }

  Future<void> challenge(String gameModeId, String ticketId) async {
    if (state.busy || state.isMatched || state.isReady || ticketId.isEmpty) return;
    state = state.copyWith(busy: true, phase: MatchmakingPhase.pairing, clearError: true, clearMatch: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck(
        'matchmaking:join',
        {'gameModeId': gameModeId, 'ticketId': ticketId},
      );
      _applyAck(ack, fallbackModeId: gameModeId);
      unawaited(ref.read(walletControllerProvider.notifier).refresh());
      if (ack['ok'] != true) {
        state = state.copyWith(phase: MatchmakingPhase.browsing);
        unawaited(refreshLobby(gameModeId));
      }
    } catch (_) {
      state = state.copyWith(
        phase: MatchmakingPhase.browsing,
        busy: false,
        error: 'Could not challenge that player. Please try again.',
      );
      unawaited(refreshLobby(gameModeId));
    }
  }

  Future<void> refreshLobby(String gameModeId) async {
    if (state.isMatched) return;
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck(
        'matchmaking:list',
        {'gameModeId': gameModeId},
      );
      if (ack['ok'] == true) {
        state = state.copyWith(readyPlayers: _parsePlayers(ack['players']));
      }
    } catch (_) {
      // Lobby refresh is best effort.
    }
  }

  Future<void> cancel() async {
    if (state.busy || state.isMatched) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('matchmaking:cancel');
      if (ack['ok'] == true) {
        state = MatchmakingState(gameModeId: state.gameModeId, readyPlayers: state.readyPlayers);
        unawaited(ref.read(walletControllerProvider.notifier).refresh());
        if (state.gameModeId != null) await refreshLobby(state.gameModeId!);
      } else {
        state = state.copyWith(busy: false, error: _ackMessage(ack));
      }
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Could not cancel ready status.');
    }
  }

  Future<void> recover() async {
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('matchmaking:status');
      if (ack['ok'] == true) _applyAck(ack);
    } catch (_) {
      // Reconnect recovery is best effort.
    }
  }

  void markEnteringMatch() {
    if (state.match == null) return;
    state = state.copyWith(phase: MatchmakingPhase.enteringMatch);
    _lobbyRefreshTimer?.cancel();
    unawaited(_unsubscribeLobby());
  }

  void resetLocal() {
    _lobbyRefreshTimer?.cancel();
    state = const MatchmakingState();
  }

  String opponentDisplayName() {
    final selfId = ref.read(authControllerProvider).user?.id;
    final match = state.match;
    if (match == null || selfId == null) return 'Opponent';
    return match.opponentName(selfId) ?? 'Opponent';
  }

  String selfDisplayName() {
    return ref.read(authControllerProvider).user?.fullName ?? 'You';
  }

  void _startLobbyRefresh(String gameModeId) {
    _lobbyRefreshTimer?.cancel();
    _lobbyRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (state.isMatched) return;
      unawaited(refreshLobby(gameModeId));
    });
  }

  Future<void> _subscribeLobby(String gameModeId) async {
    if (_subscribedModeId == gameModeId) return;
    await _unsubscribeLobby();
    final ack = await ref.read(gameSocketServiceProvider).emitWithAck(
      'matchmaking:subscribe',
      {'gameModeId': gameModeId},
    );
    if (ack['ok'] == true) {
      _subscribedModeId = gameModeId;
      state = state.copyWith(readyPlayers: _parsePlayers(ack['players']));
    }
  }

  Future<void> _unsubscribeLobby() async {
    final modeId = _subscribedModeId;
    if (modeId == null) return;
    _subscribedModeId = null;
    try {
      await ref.read(gameSocketServiceProvider).emitWithAck(
        'matchmaking:unsubscribe',
        {'gameModeId': modeId},
      );
    } catch (_) {
      // Unsubscribe is best effort.
    }
  }

  void _onRealtimeEvent(RealtimeEvent event) {
    if (event.name == 'matchmaking:matched') {
      _applyMatchedPayload(event.data);
      return;
    }

    if (event.name == 'matchmaking:lobby_updated') {
      final data = event.data;
      final modeId = data['gameModeId']?.toString();
      if (modeId == null || modeId != state.gameModeId || state.isMatched) return;
      state = state.copyWith(readyPlayers: _parsePlayers(data['players']));
    }
  }

  void _applyAck(Map<String, dynamic> ack, {String? fallbackModeId}) {
    if (ack['ok'] != true) {
      state = state.copyWith(busy: false, error: _ackMessage(ack));
      return;
    }

    final status = ack['status']?.toString() ?? 'IDLE';
    if (status == 'MATCHED') {
      _applyMatchedPayload(ack, fallbackModeId: fallbackModeId);
      return;
    }

    final players = _parsePlayers(ack['players']);
    final phase = status == 'QUEUED'
        ? (players.length >= 2 ? MatchmakingPhase.pairing : MatchmakingPhase.waitingInLobby)
        : MatchmakingPhase.browsing;

    state = MatchmakingState(
      phase: phase,
      gameModeId: ack['gameModeId']?.toString() ?? fallbackModeId,
      ticketId: ack['ticketId']?.toString(),
      matchId: ack['matchId']?.toString(),
      readyPlayers: players,
    );
  }

  void _applyMatchedPayload(Map<String, dynamic> data, {String? fallbackModeId}) {
    final rawMatch = data['match'];
    if (rawMatch is! Map) return;
    final match = MatchSummary.fromJson(Map<String, dynamic>.from(rawMatch));
    _lobbyRefreshTimer?.cancel();
    state = MatchmakingState(
      phase: MatchmakingPhase.matchFound,
      gameModeId: data['gameModeId']?.toString() ?? fallbackModeId,
      match: match,
      matchId: match.id,
    );
  }

  List<ReadyPlayer> _parsePlayers(Object? raw) {
    if (raw is! List) return const [];
    final selfId = ref.read(authControllerProvider).user?.id;
    return raw
        .whereType<Map>()
        .map((item) {
          final player = ReadyPlayer.fromJson(Map<String, dynamic>.from(item));
          if (selfId != null && player.userId == selfId) {
            return ReadyPlayer(
              ticketId: player.ticketId,
              userId: player.userId,
              displayName: player.displayName,
              readyAtMs: player.readyAtMs,
              stakeAmountMinor: player.stakeAmountMinor,
              isSelf: true,
            );
          }
          return player;
        })
        .where((player) => player.ticketId.isNotEmpty)
        .toList();
  }

  String _ackMessage(Map<String, dynamic> ack) {
    final code = ack['code']?.toString();
    switch (code) {
      case 'INSUFFICIENT_BALANCE':
      case 'INSUFFICIENT_BALANCE_FOR_MATCH':
        return 'Your available balance is too low for this room.';
      case 'ALREADY_IN_MATCHMAKING':
        return 'You are already ready in another room.';
      case 'GAME_MODE_NOT_AVAILABLE':
        return 'This Ludo room is not available right now.';
      case 'READY_PLAYER_NOT_FOUND':
        return 'That player is no longer ready. The lobby was refreshed.';
      case 'CANNOT_CHALLENGE_SELF':
        return 'Choose another ready player to start a match.';
      case 'RESOURCE_BUSY':
        return 'The live lobby is updating. Please try again in a moment.';
      case 'ACK_TIMEOUT':
        return 'The server is taking longer than expected. Your status will be recovered automatically.';
      default:
        return ack['message']?.toString() ?? 'Matchmaking request failed.';
    }
  }
}

final matchmakingControllerProvider = NotifierProvider<MatchmakingController, MatchmakingState>(
  MatchmakingController.new,
);
