import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:friends_game_app/core/config/app_config.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/core/storage/secure_storage.dart';

const _forwardedServerEvents = <String>[
  'session:ready',
  'wallet:updated',
  'broadcast:changed',
  'feedback:changed',
  'session:error',
  'lobby:player_joined',
  'lobby:player_left',
  'lobby:player_ready',
  'lobby:player_unready',
  'lobby:player_busy',
  'lobby:player_available',
  'lobby:chat:message',
  'chat:direct:message',
  'chat:direct:read',
  'challenge:created',
  'challenge:received',
  'challenge:accepted',
  'challenge:rejected',
  'challenge:cancelled',
  'challenge:expired',
  'match:started',
  'match:ready',
  'match:chat:message',
  'match:reaction',
  'match:finished',
  'match:cancelled',
  'ludo:starting_roll',
  'ludo:starting_roll_tie',
  'ludo:turn_started',
  'ludo:dice_rolled',
  'ludo:legal_moves_ready',
  'ludo:no_legal_move',
  'ludo:third_six_forfeited',
  'ludo:token_moved',
  'ludo:token_captured',
  'ludo:token_finished',
  'ludo:extra_roll_granted',
  'ludo:player_finished',
  'ludo:player_resigned',
  'ludo:auto_played',
  'ludo:strikes',
  'dama:piece_moved',
  'dama:turn_started',
  'dama:player_resigned',
  'dama:auto_played',
  'dama:strikes',
  'karta:round_started',
  'karta:rank_called',
  'karta:card_flipped',
  'karta:round_won',
  'karta:player_resigned',
  'karta:auto_played',
  'karta:strikes',
];

enum GameSocketStatus { disconnected, connecting, connected, recovering }

class GameSocketService {
  GameSocketService(this._storage, {Future<String?> Function()? refreshToken}) : _refreshToken = refreshToken;

  final SecureStorage _storage;

  /// Gets a new access token (the HTTP client's refresh). The socket's token
  /// is checked when it connects, so an expired one must be replaced first.
  final Future<String?> Function()? _refreshToken;

  /// One refresh per rejection: a token the server still refuses ends there.
  bool _authRetried = false;
  io.Socket? _socket;
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _statuses = StreamController<GameSocketStatus>.broadcast();
  GameSocketStatus _status = GameSocketStatus.disconnected;
  Duration _serverOffset = Duration.zero;
  Completer<void>? _connectCompleter;

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<GameSocketStatus> get statuses => _statuses.stream;
  GameSocketStatus get status => _status;
  bool get isConnected => _socket?.connected == true;
  DateTime serverNow() => DateTime.now().toUtc().add(_serverOffset);

  Future<void> connect() async {
    if (isConnected) return;
    final inFlight = _connectCompleter;
    if (inFlight != null) return inFlight.future;

    final completer = Completer<void>();
    _connectCompleter = completer;
    _setStatus(_socket == null ? GameSocketStatus.connecting : GameSocketStatus.recovering);

    var token = await _storage.readAccessToken();
    if (token != null && token.isNotEmpty && _expiresSoon(token)) token = await _refreshed() ?? token;
    if (token == null || token.isEmpty) {
      _setStatus(GameSocketStatus.disconnected);
      _connectCompleter = null;
      completer.completeError(StateError('AUTH_TOKEN_MISSING'));
      return completer.future;
    }

    await _disposeSocket();
    final socket = io.io(
      '${AppConfig.current.socketBaseUrl}/game',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _setStatus(GameSocketStatus.connected);
      if (!completer.isCompleted) completer.complete();
      _connectCompleter = null;
    });
    socket.onDisconnect((_) {
      _setStatus(GameSocketStatus.disconnected);
    });
    socket.onConnectError((error) {
      _setStatus(GameSocketStatus.disconnected);
      if (!completer.isCompleted) completer.completeError(StateError(error?.toString() ?? 'SOCKET_CONNECT_FAILED'));
      _connectCompleter = null;
    });
    socket.onError((error) {
      if (!isConnected) _setStatus(GameSocketStatus.disconnected);
    });
    socket.on('session:ready', (_) => _authRetried = false);
    // The server refused the token (it expired while we were away): refresh
    // once and connect again with the new one.
    socket.on('session:error', (raw) {
      final code = raw is Map ? raw['code']?.toString() : null;
      if (code != 'INVALID_ACCESS_TOKEN' || _authRetried || !identical(_socket, socket)) return;
      _authRetried = true;
      unawaited(() async {
        if (await _refreshed() != null) await reconnectWithLatestToken();
      }());
    });

    for (final eventName in _forwardedServerEvents) {
      socket.on(eventName, (raw) {
        final payload = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{'data': raw};
        final event = RealtimeEvent(name: eventName, payload: payload);
        final serverTime = event.serverTime;
        if (serverTime != null) _serverOffset = serverTime.difference(DateTime.now().toUtc());
        _events.add(event);
      });
    }

    socket.connect();
    return completer.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        _setStatus(GameSocketStatus.disconnected);
        throw TimeoutException('Socket connection timed out.');
      },
    ).whenComplete(() {
      if (identical(_connectCompleter, completer)) _connectCompleter = null;
    });
  }

  /// Request/response that (re)connects first if needed. For lobby, chat and
  /// joins, where waiting for the connection is the right thing to do.
  Future<Map<String, dynamic>> emitWithAck(
    String event, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!isConnected) await connect();
    final socket = _socket;
    if (socket == null || !socket.connected) throw StateError('SOCKET_NOT_CONNECTED');
    return _ack(socket, event, payload, const Duration(seconds: 10));
  }

  /// In-game command: never waits for a connection and gives up quickly, so a
  /// tap can't freeze the board. The caller recovers state on failure.
  Future<Map<String, dynamic>> sendCommand(
    String event,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return const {'ok': false, 'code': 'SOCKET_DISCONNECTED', 'message': 'Reconnecting…'};
    }
    return _ack(socket, event, payload, timeout);
  }

  Future<Map<String, dynamic>> _ack(io.Socket socket, String event, Map<String, dynamic> payload, Duration timeout) {
    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(event, payload, ack: (raw) {
      if (completer.isCompleted) return;
      if (raw is Map) {
        completer.complete(Map<String, dynamic>.from(raw));
      } else {
        completer.complete(<String, dynamic>{'ok': false, 'code': 'INVALID_ACK', 'message': 'Invalid server acknowledgement.'});
      }
    });

    return completer.future.timeout(
      timeout,
      onTimeout: () => <String, dynamic>{
        'ok': false,
        'code': 'ACK_TIMEOUT',
        'message': 'The server did not acknowledge the request in time.',
      },
    );
  }

  Future<String?> _refreshed() async {
    try {
      return await _refreshToken?.call();
    } catch (_) {
      return null; // offline: try with what we have
    }
  }

  /// True when the JWT's `exp` is less than a minute away (or unreadable).
  static bool _expiresSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      return expiresAt.difference(DateTime.now().toUtc()) < const Duration(minutes: 1);
    } catch (_) {
      return false;
    }
  }

  Future<void> reconnectWithLatestToken() async {
    await _disposeSocket();
    await connect();
  }

  Future<void> disconnect() async {
    await _disposeSocket();
    _setStatus(GameSocketStatus.disconnected);
  }

  void _setStatus(GameSocketStatus value) {
    if (_status == value) return;
    _status = value;
    if (!_statuses.isClosed) _statuses.add(value);
  }

  Future<void> _disposeSocket() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    socket.disconnect();
    socket.dispose();
  }

  Future<void> dispose() async {
    await _disposeSocket();
    await _events.close();
    await _statuses.close();
  }
}

final gameSocketServiceProvider = Provider<GameSocketService>((ref) {
  final service = GameSocketService(
    ref.watch(secureStorageProvider),
    refreshToken: () => ref.read(apiClientProvider).refreshAccessToken(),
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

class GameSocketStatusController extends Notifier<GameSocketStatus> {
  StreamSubscription<GameSocketStatus>? _subscription;

  @override
  GameSocketStatus build() {
    final service = ref.watch(gameSocketServiceProvider);
    _subscription?.cancel();
    _subscription = service.statuses.listen((value) => state = value);
    ref.onDispose(() => _subscription?.cancel());
    return service.status;
  }

  Future<void> connect() => ref.read(gameSocketServiceProvider).connect();
  Future<void> disconnect() => ref.read(gameSocketServiceProvider).disconnect();
}

final gameSocketStatusProvider = NotifierProvider<GameSocketStatusController, GameSocketStatus>(
  GameSocketStatusController.new,
);
