import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_challenge.dart';

class RematchState {
  const RematchState({this.finishedMatchId, this.offer, this.busy = false, this.message, this.newMatchId});

  /// The finished match this screen offers a rematch for.
  final String? finishedMatchId;
  /// The pending rematch (ours or the opponent's), if any.
  final LobbyChallenge? offer;
  final bool busy;
  final String? message;
  /// Set when the rematch was accepted: enter this match.
  final String? newMatchId;

  RematchState copyWith({LobbyChallenge? offer, bool clearOffer = false, bool? busy, String? message, bool clearMessage = false, String? newMatchId}) =>
      RematchState(
        finishedMatchId: finishedMatchId,
        offer: clearOffer ? null : offer ?? this.offer,
        busy: busy ?? this.busy,
        message: clearMessage ? null : message ?? this.message,
        newMatchId: newMatchId ?? this.newMatchId,
      );
}

/// Rematch flow for the result screen. The server owns the offer; this only
/// mirrors it, and re-reads it (`challenge:active`) after a reconnect.
class RematchController extends Notifier<RematchState> {
  final _uuid = const Uuid();
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<GameSocketStatus>? _statuses;

  @override
  RematchState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    _events?.cancel();
    _statuses?.cancel();
    _events = socket.events.listen(_onEvent);
    _statuses = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected && state.finishedMatchId != null) unawaited(_recover());
    });
    ref.onDispose(() {
      _events?.cancel();
      _statuses?.cancel();
    });
    return const RematchState();
  }

  Future<void> attach(String finishedMatchId) async {
    if (state.finishedMatchId == finishedMatchId) return;
    state = RematchState(finishedMatchId: finishedMatchId);
    await _recover();
  }

  Future<void> request() async {
    final matchId = state.finishedMatchId;
    if (matchId == null || state.busy || state.offer != null) return;
    final ack = await _send('challenge:rematch', {'matchId': matchId});
    _applyOfferAck(ack);
  }

  Future<void> accept() async {
    final offer = state.offer;
    if (offer == null || state.busy) return;
    final ack = await _send('challenge:accept', {'challengeId': offer.id});
    final data = ack['data'];
    final newMatchId = ack['ok'] == true && data is Map ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data)).matchId : null;
    if (newMatchId != null) {
      state = state.copyWith(busy: false, newMatchId: newMatchId);
    } else if (ack['ok'] != true) {
      state = state.copyWith(busy: false, clearOffer: true, message: _message(ack));
    }
  }

  Future<void> decline() => _end('challenge:reject');
  Future<void> cancel() => _end('challenge:cancel');

  Future<void> _end(String event) async {
    final offer = state.offer;
    if (offer == null || state.busy) return;
    final ack = await _send(event, {'challengeId': offer.id});
    state = state.copyWith(busy: false, clearOffer: ack['ok'] == true, message: ack['ok'] == true ? null : _message(ack));
  }

  Future<void> _recover() async {
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('challenge:active');
      final data = ack['data'];
      final offer = data is Map ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data)) : null;
      state = offer != null && offer.isRematch && offer.sourceMatchId == state.finishedMatchId
          ? state.copyWith(offer: offer)
          : state.copyWith(clearOffer: true);
    } catch (_) {
      // Offer events still arrive; recovery is retried on the next reconnect.
    }
  }

  void _onEvent(RealtimeEvent event) {
    final data = event.data;
    if (event.name == 'match:ready') {
      final match = data['match'];
      final id = match is Map ? match['id']?.toString() : null;
      if (state.offer != null && id != null) state = state.copyWith(busy: false, newMatchId: id);
      return;
    }
    if (!event.name.startsWith('challenge:') || data['kind'] != 'REMATCH') return;
    final challenge = LobbyChallenge.fromJson(data);
    if (challenge.sourceMatchId != state.finishedMatchId) return;

    switch (event.name) {
      case 'challenge:created':
      case 'challenge:received':
        state = state.copyWith(offer: challenge, busy: false, clearMessage: true);
      case 'challenge:accepted':
        state = state.copyWith(busy: false, newMatchId: challenge.matchId);
      case 'challenge:rejected':
        state = state.copyWith(clearOffer: true, busy: false, message: 'Rematch declined.');
      case 'challenge:cancelled':
        state = state.copyWith(clearOffer: true, busy: false, message: 'Rematch cancelled.');
      case 'challenge:expired':
        state = state.copyWith(clearOffer: true, busy: false, message: 'Rematch offer expired.');
    }
  }

  Future<Map<String, dynamic>> _send(String event, Map<String, dynamic> payload) async {
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      return await ref.read(gameSocketServiceProvider).emitWithAck(event, {'commandId': _uuid.v4(), ...payload});
    } catch (_) {
      return {'ok': false, 'message': 'Connection problem. Try again.'};
    }
  }

  void _applyOfferAck(Map<String, dynamic> ack) {
    final data = ack['data'];
    state = ack['ok'] == true && data is Map
        ? state.copyWith(busy: false, offer: LobbyChallenge.fromJson(Map<String, dynamic>.from(data)))
        : state.copyWith(busy: false, message: _message(ack));
  }

  String _message(Map<String, dynamic> ack) => switch (ack['code']?.toString()) {
        'CHALLENGE_ALREADY_PENDING' => 'A rematch is already pending.',
        'REMATCH_EXPIRED' => 'The rematch window has closed.',
        'INSUFFICIENT_BALANCE_FOR_MATCH' => 'A player does not have enough balance for the stake.',
        'LOBBY_ACTIVE_MATCH' => 'A player is already in another match.',
        'CHALLENGE_NOT_PENDING' || 'CHALLENGE_EXPIRED' => 'That rematch is no longer available.',
        _ => ack['message']?.toString() ?? 'Rematch request failed.',
      };
}

final rematchControllerProvider = NotifierProvider<RematchController, RematchState>(RematchController.new);
