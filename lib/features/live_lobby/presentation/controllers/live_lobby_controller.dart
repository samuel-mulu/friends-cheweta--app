import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/domain/chat_message.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_challenge.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';

/// A game's live lobby: everyone at every stake. The player sits at one stake
/// ([myStakeId]); the list can be filtered to one stake ([filterStakeId]).
class LiveLobbyState {
  const LiveLobbyState({
    this.gameCode,
    this.stakes = const [],
    this.myStakeId,
    this.filterStakeId,
    this.currentUserId,
    this.myState = LobbyPlayerState.online,
    this.players = const [],
    this.activeChallenge,
    this.loading = false,
    this.busy = false,
    this.error,
    this.acceptedMatchId,
    this.acceptedGameCode,
    this.messages = const [],
    this.sendingMessage = false,
    this.pendingChallengeUserId,
    this.chatUnread = 0,
  });

  /// Set while the lobby screen is open.
  final String? gameCode;

  /// The game's stakes, smallest first (from the catalog).
  final List<GameMode> stakes;
  final String? myStakeId;

  /// Null shows every stake.
  final String? filterStakeId;

  /// Authoritative authenticated user id — never derived from room `isSelf`.
  final String? currentUserId;
  final LobbyPlayerState myState;
  final List<LobbyPlayer> players;
  final LobbyChallenge? activeChallenge;
  final bool loading;
  final bool busy;
  final String? error;
  final String? acceptedMatchId;

  /// Game of [acceptedMatchId] when the server said (it may differ from this lobby's).
  final String? acceptedGameCode;
  final List<ChatMessage> messages;
  final bool sendingMessage;
  final String? pendingChallengeUserId;
  final int chatUnread;

  bool get isOpen => gameCode != null;
  bool get isReady => myState == LobbyPlayerState.ready;
  bool get isChallenged => myState == LobbyPlayerState.challenged;
  bool get isRecovering => loading;

  GameMode? get myStake => stakeById(myStakeId);

  /// Catalog stakes, plus custom stakes while someone (or I) sits at them.
  List<GameMode> get visibleStakes =>
      stakes.where((stake) => !stake.custom || stake.id == myStakeId || players.any((p) => p.gameModeId == stake.id)).toList();

  /// Kept for older call sites: the stake the player sits at.
  GameMode? get mode => myStake;

  /// Rules version (game type, e.g. Dama እግረኛ / ታንከኛ) of the stake I sit at.
  String? get myRules => myStake?.rulesVersion;

  /// Whether the catalog has stakes of every one of [rulesVersions], so a
  /// type picker makes sense.
  bool offersAll(Iterable<String> rulesVersions) =>
      rulesVersions.every((rules) => stakes.any((stake) => !stake.custom && stake.rulesVersion == rules));

  /// [visibleStakes] of one rules version.
  List<GameMode> stakesOfRules(String rulesVersion) => visibleStakes.where((stake) => stake.rulesVersion == rulesVersion).toList();

  /// Where switching to [rulesVersion] lands: the catalog stake of [amountMinor]
  /// of that type if there is one, else its smallest catalog stake.
  GameMode? stakeForRules(String rulesVersion, {int? amountMinor}) {
    GameMode? smallest;
    for (final stake in stakes) {
      if (stake.custom || stake.rulesVersion != rulesVersion) continue;
      if (stake.stakeAmountMinor == amountMinor) return stake;
      if (smallest == null || stake.stakeAmountMinor < smallest.stakeAmountMinor) smallest = stake;
    }
    return smallest;
  }

  /// Other players ready at a stake of [rulesVersion].
  int readyCountOfRules(String rulesVersion) =>
      players.where((p) => p.isReady && !isMe(p.userId) && stakeById(p.gameModeId)?.rulesVersion == rulesVersion).length;

  GameMode? stakeById(String? id) {
    for (final stake in stakes) {
      if (stake.id == id) return stake;
    }
    return null;
  }

  bool isMe(String userId) => currentUserId != null && userId == currentUserId;

  LobbyPlayer? get selfPlayer {
    final me = currentUserId;
    if (me == null) return null;
    for (final player in players) {
      if (player.userId == me) return player;
    }
    return null;
  }

  /// Other players, ready first (longest waiting first), then online, then busy.
  List<LobbyPlayer> get orderedPlayers {
    final me = currentUserId;
    final copy = [...players.where((player) => me == null || player.userId != me)];
    copy.sort((a, b) {
      final rank = _rank(a.state).compareTo(_rank(b.state));
      if (rank != 0) return rank;
      if (a.state == LobbyPlayerState.ready && b.state == LobbyPlayerState.ready) {
        final readyRank = (a.readyAt?.millisecondsSinceEpoch ?? 0).compareTo(b.readyAt?.millisecondsSinceEpoch ?? 0);
        if (readyRank != 0) return readyRank;
      }
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return copy;
  }

  /// [orderedPlayers] at the filtered stake (or all).
  List<LobbyPlayer> get visiblePlayers =>
      filterStakeId == null ? orderedPlayers : orderedPlayers.where((p) => p.gameModeId == filterStakeId).toList();

  int get onlineCount => players.length;
  int get readyCount => players.where((p) => p.isReady && !isMe(p.userId)).length;
  int readyCountAt(String stakeId) => players.where((p) => p.isReady && p.gameModeId == stakeId && !isMe(p.userId)).length;

  /// Apply a room/snapshot player delta using auth identity, not network `isSelf`.
  LiveLobbyState upsertPlayer(LobbyPlayer incoming, {bool clearBusy = true}) {
    final me = isMe(incoming.userId);
    final player = incoming.copyWith(isSelf: me);
    final next = [...players.where((p) => p.userId != player.userId), player];
    return copyWith(
      players: next,
      myState: me ? player.state : myState,
      myStakeId: me ? player.gameModeId : myStakeId,
      busy: clearBusy ? false : busy,
      clearError: true,
    );
  }

  LiveLobbyState markPlayer(String userId, LobbyPlayerState nextState) {
    return copyWith(
      players: [
        for (final player in players) player.userId == userId ? player.copyWith(state: nextState, isSelf: isMe(userId)) : player,
      ],
      myState: isMe(userId) ? nextState : myState,
      busy: false,
    );
  }

  /// Leaving peer must never flip local myState.
  LiveLobbyState removePlayer(String userId) => copyWith(players: players.where((p) => p.userId != userId).toList());

  LiveLobbyState withNormalizedPlayers(List<LobbyPlayer> raw) =>
      copyWith(players: [for (final player in raw) player.copyWith(isSelf: isMe(player.userId))]);

  LiveLobbyState copyWith({
    String? gameCode,
    List<GameMode>? stakes,
    String? myStakeId,
    String? filterStakeId,
    bool clearFilter = false,
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
    String? acceptedGameCode,
    bool clearAcceptedMatch = false,
    List<ChatMessage>? messages,
    bool? sendingMessage,
    String? pendingChallengeUserId,
    bool clearPendingChallenge = false,
    int? chatUnread,
  }) {
    return LiveLobbyState(
      gameCode: gameCode ?? this.gameCode,
      stakes: stakes ?? this.stakes,
      myStakeId: myStakeId ?? this.myStakeId,
      filterStakeId: clearFilter ? null : filterStakeId ?? this.filterStakeId,
      currentUserId: currentUserId ?? this.currentUserId,
      myState: myState ?? this.myState,
      players: players ?? this.players,
      activeChallenge: clearChallenge ? null : activeChallenge ?? this.activeChallenge,
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      error: clearError ? null : error ?? this.error,
      acceptedMatchId: clearAcceptedMatch ? null : acceptedMatchId ?? this.acceptedMatchId,
      acceptedGameCode: clearAcceptedMatch ? null : acceptedGameCode ?? this.acceptedGameCode,
      messages: messages ?? this.messages,
      sendingMessage: sendingMessage ?? this.sendingMessage,
      pendingChallengeUserId: clearPendingChallenge ? null : pendingChallengeUserId ?? this.pendingChallengeUserId,
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
    // Rejoin after a reconnect only while the lobby screen is open (gameCode
    // is cleared by leave()), so an app resume never creates ghost presence.
    _statuses = socket.statuses.listen((status) {
      final gameCode = state.gameCode;
      if (status == GameSocketStatus.connected && gameCode != null) {
        unawaited(open(gameCode, stakes: state.stakes, stakeId: state.myStakeId));
      }
    });
    ref.onDispose(() {
      _events?.cancel();
      _statuses?.cancel();
    });
    return LiveLobbyState(currentUserId: currentUserId);
  }

  /// Open [gameCode]'s lobby, sitting at [stakeId] (or where the server keeps us).
  /// [rulesVersion] (with [customStakeMinor]) picks the custom stake's game type.
  Future<void> open(
    String gameCode, {
    required List<GameMode> stakes,
    String? stakeId,
    int? customStakeMinor,
    String? rulesVersion,
  }) async {
    final currentUserId = ref.read(authControllerProvider).user?.id;
    final sorted = [...stakes]..sort((a, b) => a.stakeAmountMinor.compareTo(b.stakeAmountMinor));
    state = state.copyWith(
      gameCode: gameCode,
      stakes: sorted,
      currentUserId: currentUserId,
      loading: true,
      clearError: true,
    );
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('lobby:join_game', {
        'commandId': _uuid.v4(),
        'gameCode': gameCode,
        if (stakeId != null && customStakeMinor == null) 'gameModeId': stakeId,
        if (customStakeMinor != null) 'customStakeMinor': customStakeMinor,
        if (customStakeMinor != null && rulesVersion != null) 'rulesVersion': rulesVersion,
      });
      if (state.gameCode != gameCode) return; // left while waiting
      if (ack['ok'] != true) {
        state = state.copyWith(loading: false, error: _message(ack));
        return;
      }
      final data = Map<String, dynamic>.from(ack['data'] as Map? ?? const {});
      final activeChallenge =
          data['activeChallenge'] is Map ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data['activeChallenge'] as Map)) : null;
      final activeMatch = data['activeMatch'] is Map ? data['activeMatch']['id']?.toString() : null;
      final activeGame = activeMatch != null ? gameCodeOfMatch(data['activeMatch']) : activeChallenge?.matchGameCode;
      final base = LiveLobbyState(
        gameCode: gameCode,
        stakes: _stakesFrom(data['stakes'], gameCode) ?? state.stakes,
        myStakeId: data['gameModeId']?.toString() ?? stakeId,
        filterStakeId: state.filterStakeId,
        currentUserId: currentUserId,
        myState: _parseState(data['myState']),
        activeChallenge: activeChallenge,
        acceptedMatchId: activeMatch ?? activeChallenge?.matchId,
        acceptedGameCode: activeGame,
        messages: _parseMessages(data['recentMessages']),
      );
      state = base.withNormalizedPlayers(_parsePlayers(data['players']));
    } catch (_) {
      if (state.gameCode == gameCode) state = state.copyWith(loading: false, error: 'Could not open the lobby. Check your connection.');
    }
  }

  void setFilter(String? stakeId) => state = stakeId == null ? state.copyWith(clearFilter: true) : state.copyWith(filterStakeId: stakeId);

  /// Sit at another stake. A ready player stays ready (at the new stake).
  Future<void> changeStake(String stakeId, {bool keepReady = true}) async {
    final gameCode = state.gameCode;
    if (gameCode == null || stakeId == state.myStakeId || state.busy || state.isChallenged) return;
    final wasReady = state.isReady;
    await open(gameCode, stakes: state.stakes, stakeId: stakeId);
    if (keepReady && wasReady && state.myStakeId == stakeId && !state.isReady) await ready();
  }

  /// Sit at a stake of any amount (whole ETB), of game type [rulesVersion]
  /// (default: the server's). The server checks the balance.
  Future<void> playCustomStake(int amountMinor, {String? rulesVersion}) async {
    final gameCode = state.gameCode;
    if (gameCode == null || state.busy || state.isChallenged) return;
    final wasReady = state.isReady;
    await open(gameCode, stakes: state.stakes, customStakeMinor: amountMinor, rulesVersion: rulesVersion);
    if (wasReady && state.myStake?.stakeAmountMinor == amountMinor && !state.isReady) await ready();
  }

  /// Switch game type (e.g. Dama እግረኛ ↔ ታንከኛ): the same amount of that type
  /// if it has one, else its smallest stake. A ready player stays ready.
  Future<void> switchRules(String rulesVersion) async {
    if (state.myRules == rulesVersion || state.busy || state.isChallenged) return;
    final target = state.stakeForRules(rulesVersion, amountMinor: state.myStake?.stakeAmountMinor);
    if (target == null) return;
    // A stake filter of the other type would hide everything: show all.
    final filtered = state.stakeById(state.filterStakeId);
    if (filtered != null && filtered.rulesVersion != rulesVersion) state = state.copyWith(clearFilter: true);
    await changeStake(target.id);
  }

  Future<void> ready() => _simpleCommand('lobby:ready');
  Future<void> unready() => _simpleCommand('lobby:unready');

  /// Leave the lobby. Local state is reset first so a reconnect racing this
  /// call cannot rejoin.
  Future<void> leave() async {
    if (!state.isOpen) return;
    state = LiveLobbyState(currentUserId: state.currentUserId);
    try {
      await ref.read(gameSocketServiceProvider).emitWithAck('lobby:leave', {'commandId': _uuid.v4()});
    } catch (_) {}
  }

  /// Ask a ready player to play, at their stake (switching ours first if needed).
  Future<void> challenge(LobbyPlayer player, {int tokensToWin = 4}) async {
    // Being ONLINE is enough: the server readies the challenger in the same step.
    if (!player.isReady || state.busy || state.activeChallenge != null || state.isChallenged) return;
    final theirStake = player.gameModeId;
    if (theirStake != null && theirStake != state.myStakeId) {
      await changeStake(theirStake, keepReady: false);
      if (state.myStakeId != theirStake) return; // the switch failed; error already shown
    }
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
      state = state.copyWith(busy: false, clearPendingChallenge: true, error: 'Could not send the request.');
    }
  }

  Future<void> accept() => _challengeCommand('challenge:accept');
  Future<void> reject() => _challengeCommand('challenge:reject');
  Future<void> cancel() => _challengeCommand('challenge:cancel');

  /// Create a shareable invite code at the player's stake.
  Future<void> createInvite({int tokensToWin = 4}) async {
    final stakeId = state.myStakeId;
    if (stakeId == null || state.busy || state.activeChallenge != null) return;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('challenge:invite_create', {
        'commandId': _uuid.v4(),
        'gameModeId': stakeId,
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

  /// Join a friend's invite; the match starts at once. `gameCode` is the
  /// invite's game (a code may belong to another game than this screen's).
  Future<({String matchId, String? gameCode})> joinInvite(String code) async {
    final ack = await ref.read(gameSocketServiceProvider).emitWithAck('challenge:invite_join', {
      'commandId': _uuid.v4(),
      'code': code.trim(),
    });
    final data = ack['data'];
    final joined = ack['ok'] == true && data is Map ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data)) : null;
    final matchId = joined?.matchId;
    if (matchId != null) return (matchId: matchId, gameCode: joined!.matchGameCode);
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

  void clearChatUnread() {
    if (state.chatUnread != 0) state = state.copyWith(chatUnread: 0);
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
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
      state = state.copyWith(busy: false, error: 'Something went wrong. Try again.');
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
      final accepted = ack['ok'] == true && data is Map ? LobbyChallenge.fromJson(Map<String, dynamic>.from(data)) : null;
      state = state.copyWith(
        busy: false,
        acceptedGameCode: accepted?.matchGameCode,
        error: ack['ok'] == true ? null : _message(ack),
        clearError: ack['ok'] == true,
        acceptedMatchId: accepted?.matchId,
      );
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Something went wrong. Try again.');
    }
  }

  bool _isThisGame(Object? stakeId) => stakeId == null || state.stakes.any((stake) => stake.id == stakeId.toString());

  /// A player sat at a stake this phone has not seen (a new custom stake):
  /// add it, modelled on the game's stakes, so its chip appears at once.
  void _learnStake(Map<String, dynamic> data) {
    final id = data['gameModeId']?.toString();
    final player = data['player'];
    final amount = player is Map ? int.tryParse(player['stakeAmountMinor']?.toString() ?? '') : null;
    if (id == null || amount == null || _isThisGame(id) || state.stakes.isEmpty) return;
    final template = state.stakes.first;
    final stake = GameMode(
      id: id,
      gameId: template.gameId,
      code: '${template.gameCode}_CUSTOM_$amount',
      name: template.name,
      playerCount: template.playerCount,
      stakeAmountMinor: amount,
      platformFeeBps: template.platformFeeBps,
      turnDurationSeconds: template.turnDurationSeconds,
      rulesVersion: template.rulesVersion,
      enabled: true,
      gameCode: template.gameCode,
      custom: true,
    );
    state = state.copyWith(stakes: [...state.stakes, stake]..sort((a, b) => a.stakeAmountMinor.compareTo(b.stakeAmountMinor)));
  }

  /// The server's stake list (catalog + live custom stakes), when it sends one.
  List<GameMode>? _stakesFrom(Object? raw, String gameCode) {
    if (raw is! List || raw.isEmpty || raw.first is! Map || (raw.first as Map)['code'] == null) return null;
    final stakes = [
      for (final item in raw.whereType<Map>()) GameMode.fromJson(Map<String, dynamic>.from(item)).withGameCode(gameCode),
    ]..sort((a, b) => a.stakeAmountMinor.compareTo(b.stakeAmountMinor));
    return stakes;
  }

  void _onEvent(RealtimeEvent event) {
    // Only meaningful while the lobby screen is open; rematches have their own controller.
    if (!state.isOpen) return;
    final data = event.data;
    if (event.name.startsWith('challenge:') && data['kind'] == 'REMATCH') return;
    if (event.name == 'lobby:player_joined' || event.name == 'lobby:player_available') _learnStake(data);
    if (event.name.startsWith('lobby:') && !_isThisGame(data['gameModeId'] ?? data['scopeId'])) return;
    switch (event.name) {
      case 'lobby:player_joined':
      case 'lobby:player_ready':
      case 'lobby:player_unready':
      case 'lobby:player_available':
        final playerRaw = data['player'];
        if (playerRaw is Map) {
          state = state.upsertPlayer(
            LobbyPlayer.fromJson(Map<String, dynamic>.from(playerRaw), gameModeId: data['gameModeId']?.toString()),
          );
        }
        break;
      case 'lobby:player_left':
        final playerRaw = data['player'];
        final userId = playerRaw is Map ? playerRaw['userId']?.toString() : null;
        // A player moving to another stake leaves one and joins the other: only
        // remove them if they are still listed at the stake they left.
        final leftStake = data['gameModeId']?.toString();
        final listed = state.players.where((p) => p.userId == userId).firstOrNull;
        if (userId != null && (leftStake == null || listed?.gameModeId == leftStake)) {
          state = state.removePlayer(userId);
        }
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
          acceptedGameCode: challenge.matchGameCode,
        );
        break;
      case 'match:ready':
        final rawMatch = data['match'];
        final matchId = rawMatch is Map ? rawMatch['id']?.toString() : null;
        if (matchId != null && matchId.isNotEmpty) {
          state = state.copyWith(
            players: const [],
            clearChallenge: true,
            acceptedMatchId: matchId,
            acceptedGameCode: gameCodeOfMatch(rawMatch),
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
    return raw.whereType<Map>().map((item) => LobbyPlayer.fromJson(Map<String, dynamic>.from(item))).toList();
  }

  List<ChatMessage> _parseMessages(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item))).toList(growable: false);
  }

  void _appendMessage(ChatMessage message) {
    if (message.id.isEmpty || state.messages.any((item) => item.id == message.id)) return;
    final next = [...state.messages, message];
    state = state.copyWith(
      messages: next.length > 50 ? next.sublist(next.length - 50) : next,
      sendingMessage: false,
      chatUnread: state.chatUnread + 1,
      clearError: true,
    );
  }

  LobbyPlayerState _parseState(Object? raw) {
    return switch (raw?.toString()) {
      'READY' => LobbyPlayerState.ready,
      'CHALLENGED' => LobbyPlayerState.challenged,
      _ => LobbyPlayerState.online,
    };
  }

  String _message(Map<String, dynamic> ack) => lobbyErrorText(ack['code']?.toString(), ack['message']?.toString());
}

/// Server error codes in words a player understands.
String lobbyErrorText(String? code, String? fallback) => switch (code) {
      'INSUFFICIENT_BALANCE_FOR_MATCH' => 'Your balance is below this stake. Add funds to play.',
      'LOBBY_ACTIVE_MATCH' => 'Finish your current match first.',
      'CHALLENGE_TARGET_NOT_READY' => 'That player is no longer ready.',
      'LOBBY_USER_BUSY' => 'That player is already in another request.',
      'LOBBY_NOT_JOINED' => 'Reconnecting to the lobby…',
      'CHALLENGE_EXPIRED' => 'The request expired.',
      'CHALLENGE_NOT_PENDING' => 'That request is no longer open.',
      'RATE_LIMITED' => 'Slow down a little and try again.',
      'ACK_TIMEOUT' || 'SOCKET_DISCONNECTED' => 'Connection is slow. Try again in a moment.',
      _ => fallback ?? 'Something went wrong. Try again.',
    };

final liveLobbyControllerProvider = NotifierProvider<LiveLobbyController, LiveLobbyState>(LiveLobbyController.new);

class InviteJoinException implements Exception {
  const InviteJoinException(this.message);
  final String message;
  @override
  String toString() => message;
}
