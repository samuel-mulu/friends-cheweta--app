import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/game_hub/data/game_hub_repository.dart';
import 'package:friends_game_app/features/karta/domain/karta_models.dart';
import 'package:friends_game_app/features/match/domain/turn_timing.dart';

/// A finished round as it looked when the matching card fell (the server has
/// already started the next round; the screen shows this for a moment).
class KartaRoundEnd {
  const KartaRoundEnd({required this.result, required this.dealt, required this.verified, required this.seq});
  final KartaRoundResult result;
  final List<KartaDealt> dealt;

  /// SHA-256(revealed seed) == the commitment published before the call.
  final bool verified;
  final int seq;
}

class KartaParticipant {
  const KartaParticipant({required this.userId, required this.fullName});
  final String userId;
  final String fullName;
  String get shortName {
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'Player' : first;
  }
}

class KartaMatchViewState {
  const KartaMatchViewState({
    this.matchId,
    this.game,
    this.timing = const TurnTiming(),
    this.participants = const [],
    this.loading = false,
    this.recovering = false,
    this.pendingCommandId,
    this.error,
    this.turnSeconds = 15,
    this.roundEnd,
    this.autoPlayedSeq = 0,
    this.autoPlayedBy,
  });

  final String? matchId;
  final KartaGame? game;
  final TurnTiming timing;
  final List<KartaParticipant> participants;
  final bool loading;
  final bool recovering;
  final String? pendingCommandId;
  final String? error;
  final int turnSeconds;
  final KartaRoundEnd? roundEnd;
  final int autoPlayedSeq;
  final String? autoPlayedBy;

  String nameOf(String? userId) => participants.where((p) => p.userId == userId).firstOrNull?.shortName ?? 'Opponent';

  KartaMatchViewState copyWith({
    KartaGame? game,
    TurnTiming? timing,
    List<KartaParticipant>? participants,
    bool? loading,
    bool? recovering,
    String? pendingCommandId,
    bool clearPending = false,
    String? error,
    bool clearError = false,
    int? turnSeconds,
    KartaRoundEnd? roundEnd,
    int? autoPlayedSeq,
    String? autoPlayedBy,
  }) =>
      KartaMatchViewState(
        matchId: matchId,
        game: game ?? this.game,
        timing: timing ?? this.timing,
        participants: participants ?? this.participants,
        loading: loading ?? this.loading,
        recovering: recovering ?? this.recovering,
        pendingCommandId: clearPending ? null : pendingCommandId ?? this.pendingCommandId,
        error: clearError ? null : error ?? this.error,
        turnSeconds: turnSeconds ?? this.turnSeconds,
        roundEnd: roundEnd ?? this.roundEnd,
        autoPlayedSeq: autoPlayedSeq ?? this.autoPlayedSeq,
        autoPlayedBy: autoPlayedBy ?? this.autoPlayedBy,
      );
}

class KartaMatchController extends Notifier<KartaMatchViewState> {
  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<GameSocketStatus>? _socketSub;
  int? _openVersion;
  final Set<String> _seenEventIds = {};
  static const _uuid = Uuid();
  static const _recoverOn = {'ACK_TIMEOUT', 'MATCH_VERSION_CONFLICT', 'SEND_FAILED', 'MATCH_ROOM_NOT_JOINED'};

  @override
  KartaMatchViewState build() {
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
    return const KartaMatchViewState();
  }

  Future<void> join(String matchId) async {
    if (matchId.isEmpty || (state.matchId == matchId && state.game != null)) return;
    state = KartaMatchViewState(matchId: matchId, loading: true);
    _openVersion = null;
    _seenEventIds.clear();
    try {
      final socket = ref.read(gameSocketServiceProvider);
      await socket.connect();
      _applySnapshot(await socket.emitWithAck('karta:join', {'matchId': matchId}));
      unawaited(_loadTurnSeconds(matchId));
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not join this match. Check your connection and try again.');
    }
  }

  Future<void> recover() async {
    final matchId = state.matchId;
    if (matchId == null || state.recovering) return;
    state = state.copyWith(recovering: true, clearError: true);
    try {
      final socket = ref.read(gameSocketServiceProvider);
      if (!socket.isConnected) await socket.connect();
      _applySnapshot(await socket.emitWithAck('karta:join', {'matchId': matchId}));
    } catch (_) {
      state = state.copyWith(recovering: false, error: 'Connection restored, but match recovery is still pending.');
    }
  }

  Future<bool> call(String rank) => _command('karta:call', {'rank': rank});
  Future<bool> flip() => _command('karta:flip', const {});
  Future<bool> resign() => _command('karta:resign', const {});

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
    state = state.copyWith(error: _message(ack));
    if (_recoverOn.contains(ack['code'])) unawaited(recover());
    return false;
  }

  void _onEvent(RealtimeEvent event) {
    final game = state.game;
    if (game == null || event.matchId != state.matchId) return;
    if (!event.name.startsWith('karta:') && event.name != 'match:finished') return;
    if (event.eventId != null && !_seenEventIds.add(event.eventId!)) return;
    final data = event.data;

    if (event.name == 'karta:auto_played' || event.name == 'karta:strikes') {
      final playerId = data['playerId']?.toString();
      if (playerId == null) return;
      final strikes = int.tryParse(data['strikes']?.toString() ?? '') ?? 0;
      state = state.copyWith(
        timing: state.timing.copyWith(strikes: {...state.timing.strikes, playerId: strikes}),
        autoPlayedSeq: event.name == 'karta:auto_played' ? state.autoPlayedSeq + 1 : null,
        autoPlayedBy: event.name == 'karta:auto_played' ? playerId : null,
      );
      return;
    }

    // One command's events share a version; resync on any gap.
    final incoming = event.version;
    if (incoming == null || incoming < game.version) return;
    if (incoming == game.version && _openVersion != incoming) return;
    if (incoming > game.version + 1) {
      _openVersion = null;
      unawaited(recover());
      return;
    }
    _openVersion = incoming;

    var next = game.copyWith(version: incoming);
    KartaRoundEnd? roundEnd;
    switch (event.name) {
      case 'karta:rank_called':
        // Now the starter deals; the first card goes to the chooser.
        next = next.copyWith(calledRank: data['rank']?.toString(), calling: false, currentPlayerId: game.starterId, receiverId: game.callerId);
      case 'karta:card_flipped':
        final receiver = data['playerId']?.toString() ?? '';
        next = next.copyWith(
          dealt: [...game.dealt, KartaDealt(KartaCard.parse(data['card']?.toString() ?? 'AS'), receiver)],
          receiverId: game.otherThan(receiver),
        );
      case 'karta:round_won':
        final result = KartaRoundResult.fromJson(data['result']);
        next = next.copyWith(scores: _scores(data['scores']) ?? game.scores, lastRound: result, clearCurrentPlayer: true, clearReceiver: true);
        if (result != null) {
          roundEnd = KartaRoundEnd(
            result: result,
            dealt: game.dealt,
            verified: sha256.convert(utf8.encode(result.seed)).toString() == game.deckCommitment,
            seq: (state.roundEnd?.seq ?? 0) + 1,
          );
        }
      case 'karta:round_started':
        next = next.copyWith(
          round: int.tryParse(data['round']?.toString() ?? '') ?? game.round + 1,
          starterId: data['starterId']?.toString(),
          callerId: data['callerId']?.toString(),
          calling: true,
          clearCalledRank: true,
          clearReceiver: true,
          currentPlayerId: data['callerId']?.toString(),
          dealt: const [],
          deckCommitment: data['deckCommitment']?.toString(),
          scores: _scores(data['scores']),
        );
      case 'match:finished':
        next = next.copyWith(
          finished: true,
          clearCurrentPlayer: true,
          winnerOrder: (data['winnerOrder'] as List? ?? const []).map((e) => e.toString()).toList(),
          finishReason: data['reason']?.toString(),
          scores: _scores(data['scores']),
        );
    }

    // Every accepted action restarts the clock of whoever must act next.
    final timing = next.finished
        ? state.timing.copyWith(version: incoming, clearClock: true)
        : next.currentPlayerId != null && event.name != 'karta:round_won'
            ? state.timing.copyWith(
                version: incoming,
                playerId: next.currentPlayerId,
                turnEndsAt: DateTime.now().add(Duration(seconds: state.turnSeconds)),
              )
            : null;
    state = state.copyWith(game: next, timing: timing, roundEnd: roundEnd, clearPending: true, clearError: true);
  }

  Map<String, int>? _scores(Object? raw) =>
      raw is Map ? raw.map((key, value) => MapEntry(key.toString(), int.tryParse(value.toString()) ?? 0)) : null;

  void _applySnapshot(Map<String, dynamic> ack) {
    if (ack['ok'] != true || ack['state'] is! Map) {
      state = state.copyWith(loading: false, recovering: false, error: _message(ack));
      return;
    }
    final raw = Map<String, dynamic>.from(ack['state'] as Map);
    _openVersion = null;
    state = state.copyWith(
      game: KartaGame.fromJson(Map<String, dynamic>.from(raw['game'] as Map? ?? const {})),
      timing: ack['timing'] is Map ? TurnTiming.fromJson(Map<String, dynamic>.from(ack['timing'] as Map)) : state.timing,
      participants: (ack['participants'] as List? ?? const [])
          .whereType<Map>()
          .map((p) => KartaParticipant(userId: p['userId']?.toString() ?? '', fullName: p['fullName']?.toString() ?? 'Player'))
          .toList(),
      loading: false,
      recovering: false,
      clearPending: true,
      clearError: true,
    );
  }

  Future<void> _loadTurnSeconds(String matchId) async {
    try {
      final json = await ref.read(gameHubRepositoryProvider).getMatch(matchId);
      final mode = json['gameMode'];
      final seconds = mode is Map ? int.tryParse(mode['turnDurationSeconds']?.toString() ?? '') : null;
      if (seconds != null && seconds > 0) state = state.copyWith(turnSeconds: seconds);
    } catch (_) {}
  }

  String _message(Map<String, dynamic> ack) => switch (ack['code']?.toString()) {
        'NOT_PLAYER_TURN' => 'It is not your turn.',
        'INVALID_TURN_PHASE' => 'That is not possible right now.',
        'MATCH_VERSION_CONFLICT' => 'The table changed. Syncing…',
        'MATCH_ROOM_NOT_JOINED' => 'Rejoining the match room…',
        'MATCH_NOT_PLAYING' => 'This match has ended.',
        'SOCKET_DISCONNECTED' => 'Reconnecting… your move was not sent.',
        'ACK_TIMEOUT' || 'SEND_FAILED' => 'Slow connection. Syncing the table…',
        _ => ack['message']?.toString() ?? 'The game request failed.',
      };
}

final kartaMatchControllerProvider = NotifierProvider<KartaMatchController, KartaMatchViewState>(KartaMatchController.new);
