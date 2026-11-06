import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/domain/chat_message.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_challenge.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';

class LiveLobbyState {
  const LiveLobbyState({
    this.mode,
    this.currentUserId,
    this.myState = LobbyPlayerState.online,
    this.players = const [],
    this.activeChallenge,
    this.loading = false,
    this.busy = false,
    this.error,
    this.acceptedMatchId,
    this.messages = const [],
    this.sendingMessage = false,
    this.pendingChallengeUserId,
    this.chatUnread = 0,
  });

  final GameMode? mode;
  /// Authoritative authenticated user id — never derived from room `isSelf`.
  final String? currentUserId;
  final LobbyPlayerState myState;
  final List<LobbyPlayer> players;
  final LobbyChallenge? activeChallenge;
  final bool loading;
  final bool busy;
  final String? error;
  final String? acceptedMatchId;
  final List<ChatMessage> messages;
  final bool sendingMessage;
  final String? pendingChallengeUserId;
  final int chatUnread;

  int get onlineCount => players.length;
  int get readyCount =>
      players.where((player) => player.state == LobbyPlayerState.ready).length;
  bool get isReady => myState == LobbyPlayerState.ready;
  bool get isChallenged => myState == LobbyPlayerState.challenged;
  bool get isRecovering => loading;

  bool isMe(String userId) => currentUserId != null && userId == currentUserId;

  LobbyPlayer? get selfPlayer {
    final me = currentUserId;
    if (me == null) return null;
    for (final player in players) {
      if (player.userId == me) return player;
    }
    return null;
  }

  List<LobbyPlayer> get orderedPlayers {
    final me = currentUserId;
    final copy = [
      ...players.where((player) => me == null || player.userId != me),
    ];
    copy.sort((a, b) {
      final rank = _rank(a.state).compareTo(_rank(b.state));
      if (rank != 0) return rank;
      if (a.state == LobbyPlayerState.ready && b.state == LobbyPlayerState.ready) {
        final readyRank = (a.readyAt?.millisecondsSinceEpoch ?? 0)
            .compareTo(b.readyAt?.millisecondsSinceEpoch ?? 0);
        if (readyRank != 0) return readyRank;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return copy;
  }

  /// Apply a room/snapshot player delta using auth identity, not network `isSelf`.
  LiveLobbyState upsertPlayer(LobbyPlayer incoming, {bool clearBusy = true}) {
    final me = isMe(incoming.userId);
    final player = incoming.copyWith(isSelf: me);
    final next = [
      ...players.where((p) => p.userId != player.userId),
      player,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    return copyWith(
      players: next,
      myState: me ? player.state : myState,
      busy: clearBusy ? false : busy,
      clearError: true,
    );
  }

  LiveLobbyState markPlayer(String userId, LobbyPlayerState nextState) {
    return copyWith(
      players: [
        for (final player in players)
          player.userId == userId ? player.copyWith(state: nextState, isSelf: isMe(userId)) : player,
      ],
      myState: isMe(userId) ? nextState : myState,
      busy: false,
    );
  }

  LiveLobbyState removePlayer(String userId) {
    return copyWith(
      players: players.where((p) => p.userId != userId).toList(),
      // Leaving peer must never flip local myState.
    );
  }

  LiveLobbyState withNormalizedPlayers(List<LobbyPlayer> raw) {
    return copyWith(
      players: [
        for (final player in raw) player.copyWith(isSelf: isMe(player.userId)),
      ],
    );
  }

  LiveLobbyState copyWith({
    GameMode? mode,
    String? currentUserId,
    LobbyPlayerState? myState,
    List<LobbyPlayer>? players,
    LobbyChallenge? activeChallenge,
    bool clearChallenge = false,
    bool? loading,
    bool? busy,
    String? error,
    bool clearError = false,
    String? acceptedMatchId,
    bool clearAcceptedMatch = false,
    List<ChatMessage>? messages,
    bool? sendingMessage,
    String? pendingChallengeUserId,
    bool clearPendingChallenge = false,
    int? chatUnread,
  }) {
    return LiveLobbyState(
      mode: mode ?? this.mode,
      currentUserId: currentUserId ?? this.currentUserId,
      myState: myState ?? this.myState,
      players: players ?? this.players,
      activeChallenge: clearChallenge ? null : activeChallenge ?? this.activeChallenge,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
      acceptedMatchId: clearAcceptedMatch ? null : acceptedMatchId ?? this.acceptedMatchId,
      messages: messages ?? this.messages,
      sendingMessage: sendingMessage ?? this.sendingMessage,
      pendingChallengeUserId:
          clearPendingChallenge ? null : pendingChallengeUserId ?? this.pendingChallengeUserId,
      chatUnread: chatUnread ?? this.chatUnread,
    );
  }

  static int _rank(LobbyPlayerState state) => switch (state) {
        LobbyPlayerState.ready => 0,
        LobbyPlayerState.online => 1,
        LobbyPlayerState.challenged => 2,
      };
}

class LiveLobbyController extends Notifier<LiveLobbyState> {
  final _uuid = const Uuid();
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<GameSocketStatus>? _statuses;

  @override
  LiveLobbyState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    final currentUserId = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    _events?.cancel();
    _statuses?.cancel();
    _events = socket.events.listen(_onEvent);
    // Rejoin after a reconnect only while the lobby screen is open (mode is
    // cleared by leave()), so an app resume never creates ghost presence.
    _statuses = socket.statuses.listen((status) {
      final mode = state.mode;
      if (status == GameSocketStatus.connected && mode != null) unawaited(join(mode));
    });
    ref.onDispose(() {
      _events?.cancel();
      _statuses?.cancel();
    });
    return LiveLobbyState(currentUserId: currentUserId);
  }

  Future<void> join(GameMode mode) async {
    final currentUserId = ref.read(authControllerProvider).user?.id;
    state = state.copyWith(
      mode: mode,
      currentUserId: currentUserId,
      loading: true,
      clearError: true,
    );
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('lobby:join', {
        'commandId': _uuid.v4(),
        'gameModeId': mode.id,
      });
      if (ack['ok'] == true) {
        final data = Map<String, dynamic>.from(ack['data'] as Map? ?? const {});
        final activeChallenge = data['activeChallenge'] is Map
            ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data['activeChallenge'] as Map))
            : null;
        final activeMatch = data['activeMatch'] is Map ? data['activeMatch']['id']?.toString() : null;
        final base = LiveLobbyState(
          mode: mode,
          currentUserId: currentUserId,
          myState: _parseState(data['myState']),
          activeChallenge: activeChallenge,
          acceptedMatchId: activeMatch ?? activeChallenge?.matchId,
          messages: _parseMessages(data['recentMessages']),
        );
        state = base.withNormalizedPlayers(_parsePlayers(data['players']));
      } else {
        state = state.copyWith(loading: false, error: _message(ack));
      }
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not join the live lobby.');
    }
  }

  Future<void> ready() => _simpleCommand('lobby:ready');
  Future<void> unready() => _simpleCommand('lobby:unready');

  /// Leave the lobby. Local state is reset first so a reconnect racing this
  /// call cannot rejoin.
  Future<void> leave() async {
    if (state.mode == null) return;
    state = LiveLobbyState(currentUserId: state.currentUserId);
    try {
      await ref.read(gameSocketServiceProvider).emitWithAck('lobby:leave', {'commandId': _uuid.v4()});
    } catch (_) {}
  }

  Future<void> challenge(LobbyPlayer player, {int tokensToWin = 4}) async {
    // Being ONLINE is enough: the server readies the challenger in the same step.
    if (!player.isReady || state.busy || state.activeChallenge != null || state.isChallenged) return;
    state = state.copyWith(busy: true, pendingChallengeUserId: player.userId, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('challenge:create', {
        'commandId': _uuid.v4(),
        'opponentUserId': player.userId,
        'tokensToWin': tokensToWin,
      });
      if (ack['ok'] != true) {
        state = state.copyWith(busy: false, clearPendingChallenge: true, error: _message(ack));
      }
    } catch (_) {
      state = state.copyWith(busy: false, clearPendingChallenge: true, error: 'Could not send challenge.');
    }
  }

  Future<void> accept() => _challengeCommand('challenge:accept');
  Future<void> reject() => _challengeCommand('challenge:reject');
  Future<void> cancel() => _challengeCommand('challenge:cancel');

  /// Create a shareable invite code for this lobby's mode.
  Future<void> createInvite({int tokensToWin = 4}) async {
    final mode = state.mode;
    if (mode == null || state.busy || state.activeChallenge != null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('challenge:invite_create', {
        'commandId': _uuid.v4(),
        'gameModeId': mode.id,
        'tokensToWin': tokensToWin,
      });
      final data = ack['data'];
      state = ack['ok'] == true && data is Map
          ? state.copyWith(busy: false, activeChallenge: LobbyChallenge.fromJson(Map<String, dynamic>.from(data)))
          : state.copyWith(busy: false, error: _message(ack));
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Could not create an invite.');
    }
  }

  /// Join a friend's invite by code (works outside the lobby). Returns the
  /// match id to enter; throws [InviteJoinException] with a readable message.
  Future<String> joinInvite(String code) async {
    final ack = await ref.read(gameSocketServiceProvider).emitWithAck('challenge:invite_join', {
      'commandId': _uuid.v4(),
      'code': code.trim(),
    });
    final data = ack['data'];
    final matchId = ack['ok'] == true && data is Map
        ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data)).matchId
        : null;
    if (matchId != null) return matchId;
    throw InviteJoinException(switch (ack['code']?.toString()) {
      'INVITE_NOT_FOUND' => 'That code does not exist or has expired.',
      'CHALLENGE_NOT_PENDING' || 'CHALLENGE_EXPIRED' => 'That invite is no longer available.',
      'INVITE_SELF' => 'This is your own invite code.',
      'INSUFFICIENT_BALANCE_FOR_MATCH' => 'Your balance is below the stake for this game.',
      _ => _message(ack),
    });
  }

  /// True when the server accepted the message.
  Future<bool> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 160 || state.sendingMessage) return false;
    state = state.copyWith(sendingMessage: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('lobby:chat:send', {
        'commandId': _uuid.v4(),
        'text': trimmed,
      });
      state = state.copyWith(
        sendingMessage: false,
        error: ack['ok'] == true ? null : _message(ack),
        clearError: ack['ok'] == true,
      );
      return ack['ok'] == true;
    } catch (_) {
      state = state.copyWith(sendingMessage: false, error: 'Could not send message.');
      return false;
    }
  }

  Future<void> _simpleCommand(String event) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck(event, {'commandId': _uuid.v4()});
      state = state.copyWith(
        busy: false,
        error: ack['ok'] == true ? null : _message(ack),
        clearError: ack['ok'] == true,
      );
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Command failed.');
    }
  }

  Future<void> _challengeCommand(String event) async {
    final challenge = state.activeChallenge;
    if (challenge == null || state.busy) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck(event, {
        'commandId': _uuid.v4(),
        'challengeId': challenge.id,
      });
      // The accept ack carries the match too, so a lost event cannot strand the player.
      final data = ack['data'];
      final matchId = ack['ok'] == true && data is Map
          ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data)).matchId
          : null;
      state = state.copyWith(
        busy: false,
        error: ack['ok'] == true ? null : _message(ack),
        clearError: ack['ok'] == true,
        acceptedMatchId: matchId,
      );
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Challenge command failed.');
    }
  }

  void _onEvent(RealtimeEvent event) {
    // Only meaningful while the lobby screen is open; rematches have their own controller.
    if (state.mode == null) return;
    final data = event.data;
    if (event.name.startsWith('challenge:') && data['kind'] == 'REMATCH') return;
    switch (event.name) {
      case 'lobby:player_joined':
      case 'lobby:player_ready':
      case 'lobby:player_unready':
      case 'lobby:player_available':
        final playerRaw = data['player'];
        if (playerRaw is Map) {
          state = state.upsertPlayer(LobbyPlayer.fromJson(Map<String, dynamic>.from(playerRaw)));
        }
        break;
      case 'lobby:player_left':
        final playerRaw = data['player'];
        final userId = playerRaw is Map ? playerRaw['userId']?.toString() : null;
        if (userId != null) state = state.removePlayer(userId);
        break;
      case 'lobby:player_busy':
        final userId = data['userId']?.toString();
        if (userId != null) state = state.markPlayer(userId, LobbyPlayerState.challenged);
        break;
      case 'lobby:chat:message':
        _appendMessage(ChatMessage.fromJson(data));
        break;
      case 'challenge:created':
      case 'challenge:received':
        final challenge = LobbyChallenge.fromJson(data);
        state = state.copyWith(
          activeChallenge: challenge,
          // An open invite does not change our lobby state on the server.
          myState: challenge.isInvite ? null : LobbyPlayerState.challenged,
          busy: false,
          clearPendingChallenge: true,
          clearError: true,
        );
        break;
      case 'challenge:accepted':
        final challenge = LobbyChallenge.fromJson(data);
        state = state.copyWith(
          activeChallenge: challenge,
          players: const [],
          myState: LobbyPlayerState.online,
          busy: false,
          clearError: true,
          acceptedMatchId: challenge.matchId,
        );
        break;
      case 'match:ready':
        final rawMatch = data['match'];
        final matchId = rawMatch is Map ? rawMatch['id']?.toString() : null;
        if (matchId != null && matchId.isNotEmpty) {
          state = state.copyWith(
            players: const [],
            activeChallenge: null,
            clearChallenge: true,
            acceptedMatchId: matchId,
            busy: false,
            clearError: true,
          );
        }
        break;
      case 'challenge:rejected':
      case 'challenge:cancelled':
      case 'challenge:expired':
        // The server follows with lobby:player_available for every player it
        // returned to READY (including us); until then we are just online.
        final isInvite = data['kind'] == 'INVITE';
        state = state.copyWith(
          myState: isInvite ? null : LobbyPlayerState.online,
          busy: false,
          clearPendingChallenge: true,
          clearError: true,
          clearChallenge: true,
        );
        break;
    }
  }

  List<LobbyPlayer> _parsePlayers(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => LobbyPlayer.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  List<ChatMessage> _parseMessages(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  void _appendMessage(ChatMessage message) {
    if (message.id.isEmpty || state.messages.any((item) => item.id == message.id)) {
      return;
    }
    final next = [...state.messages, message];
    state = state.copyWith(
      messages: next.length > 50 ? next.sublist(next.length - 50) : next,
      sendingMessage: false,
      chatUnread: state.chatUnread + 1,
      clearError: true,
    );
  }

  void clearChatUnread() {
    if (state.chatUnread != 0) state = state.copyWith(chatUnread: 0);
  }

  LobbyPlayerState _parseState(Object? raw) {
    return switch (raw?.toString()) {
      'READY' => LobbyPlayerState.ready,
      'CHALLENGED' => LobbyPlayerState.challenged,
      _ => LobbyPlayerState.online,
    };
  }

  String _message(Map<String, dynamic> ack) =>
      ack['message']?.toString() ?? ack['code']?.toString() ?? 'Request failed.';
}

final liveLobbyControllerProvider =
    NotifierProvider<LiveLobbyController, LiveLobbyState>(LiveLobbyController.new);

class InviteJoinException implements Exception {
  const InviteJoinException(this.message);
  final String message;
  @override
  String toString() => message;
}
