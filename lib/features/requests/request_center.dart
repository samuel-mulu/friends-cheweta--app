import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_challenge.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';

/// Game requests, app-wide: someone asking me to play (from a lobby or a
/// rematch), or me waiting for an answer. One place holds the request, so it
/// is shown and answered the same way on every screen. Invites (a code shared
/// outside the app) stay in the lobby that created them.
class RequestCenterState {
  const RequestCenterState({this.request, this.busy = false, this.error, this.notice, this.openMatch});

  /// The open request, if any.
  final LobbyChallenge? request;
  final bool busy;
  final String? error;

  /// One-off message after a request ends ("Abel declined").
  final String? notice;

  /// Set when a request became a match: the app opens it.
  final ({String matchId, String? gameCode})? openMatch;

  bool isIncomingFor(String? userId) => request != null && request!.opponentId == userId;

  RequestCenterState copyWith({
    LobbyChallenge? request,
    bool clearRequest = false,
    bool? busy,
    String? error,
    bool clearError = false,
    String? notice,
    ({String matchId, String? gameCode})? openMatch,
  }) =>
      RequestCenterState(
        request: clearRequest ? null : request ?? this.request,
        busy: busy ?? this.busy,
        error: clearError ? null : error ?? this.error,
        notice: notice,
        openMatch: openMatch,
      );
}

class RequestCenter extends Notifier<RequestCenterState> {
  final _uuid = const Uuid();
  StreamSubscription<RealtimeEvent>? _events;

  @override
  RequestCenterState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    _events?.cancel();
    _events = socket.events.listen(_onEvent);
    ref.onDispose(() => _events?.cancel());
    return const RequestCenterState();
  }

  String? get _me => ref.read(authControllerProvider).user?.id;

  void _onEvent(RealtimeEvent event) {
    final data = event.data;
    switch (event.name) {
      case 'challenge:received':
      case 'challenge:created':
        final challenge = LobbyChallenge.fromJson(data);
        if (challenge.isInvite) return;
        // My own rematch offer is shown on the result screen, where I made it.
        if (challenge.isRematch && challenge.challengerId == _me) return;
        state = RequestCenterState(request: challenge);
      case 'challenge:accepted':
        final challenge = LobbyChallenge.fromJson(data);
        if (state.request?.id != challenge.id) return;
        final matchId = challenge.matchId;
        state = RequestCenterState(
          openMatch: matchId == null ? null : (matchId: matchId, gameCode: challenge.matchGameCode),
        );
      case 'challenge:rejected':
      case 'challenge:cancelled':
      case 'challenge:expired':
        final challenge = LobbyChallenge.fromJson(data);
        final open = state.request;
        if (open == null || open.id != challenge.id) return;
        final mine = open.challengerId == _me;
        final other = mine ? open.opponentName : open.challengerName;
        state = RequestCenterState(
          notice: switch (event.name) {
            'challenge:rejected' when mine => '${other ?? 'The player'} declined.',
            'challenge:cancelled' when !mine => '${other ?? 'The player'} cancelled the request.',
            'challenge:expired' => 'The request expired.',
            _ => null,
          },
        );
    }
  }

  Future<void> accept() => _command('challenge:accept');
  Future<void> decline() => _command('challenge:reject');
  Future<void> cancel() => _command('challenge:cancel');

  /// The sheet was closed by the app (match opened, notice shown).
  void consumed() {
    if (state.openMatch != null || state.notice != null) state = state.copyWith();
  }

  Future<void> _command(String event) async {
    final request = state.request;
    if (request == null || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck(event, {
        'commandId': _uuid.v4(),
        'challengeId': request.id,
      });
      if (ack['ok'] != true) {
        state = state.copyWith(busy: false, error: lobbyErrorText(ack['code']?.toString(), ack['message']?.toString()));
        return;
      }
      // The accept ack carries the match, so a lost event cannot strand the player.
      final data = ack['data'];
      final accepted = event == 'challenge:accept' && data is Map ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data)) : null;
      final matchId = accepted?.matchId;
      state = matchId != null
          ? RequestCenterState(openMatch: (matchId: matchId, gameCode: accepted!.matchGameCode))
          : event == 'challenge:accept'
              ? state.copyWith(busy: false) // the match arrives as an event
              : const RequestCenterState();
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Connection is slow. Try again in a moment.');
    }
  }
}

final requestCenterProvider = NotifierProvider<RequestCenter, RequestCenterState>(RequestCenter.new);
