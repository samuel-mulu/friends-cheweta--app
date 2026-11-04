import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/chat_inbox_controller.dart';
import 'package:friends_game_app/features/chat/domain/direct_message.dart';

class DirectChatState {
  const DirectChatState({
    this.messages = const [],
    this.loading = true,
    this.sending = false,
    this.loadingOlder = false,
    this.hasMore = true,
    this.error,
  });

  /// Oldest first.
  final List<DirectMessage> messages;
  final bool loading;
  final bool sending;
  final bool loadingOlder;
  final bool hasMore;
  final String? error;

  DirectChatState copyWith({
    List<DirectMessage>? messages,
    bool? loading,
    bool? sending,
    bool? loadingOlder,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) =>
      DirectChatState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        sending: sending ?? this.sending,
        loadingOlder: loadingOlder ?? this.loadingOlder,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : error ?? this.error,
      );
}

/// One open private conversation (keyed by the other user's id).
class DirectChatController extends AutoDisposeFamilyNotifier<DirectChatState, String> {
  static const _page = 50;
  final _uuid = const Uuid();
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<GameSocketStatus>? _statuses;

  String get _peerId => arg;

  @override
  DirectChatState build(String peerId) {
    final socket = ref.watch(gameSocketServiceProvider);
    _events = socket.events.listen(_onEvent);
    _statuses = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected) unawaited(load());
    });
    final inbox = ref.read(chatInboxControllerProvider.notifier);
    Future.microtask(() => inbox.setOpen(peerId));
    ref.onDispose(() {
      _events?.cancel();
      _statuses?.cancel();
      // Deferred: providers must not be modified while one is disposing.
      Future.microtask(() => inbox.close(peerId));
    });
    Future.microtask(load);
    return const DirectChatState();
  }

  Future<void> load() async {
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('chat:direct:history', {'peerId': _peerId});
      if (ack['ok'] == true) {
        final messages = _parse(ack['data']);
        state = state.copyWith(messages: _merge(messages), loading: false, hasMore: messages.length >= _page, clearError: true);
        unawaited(_markRead());
      } else {
        state = state.copyWith(loading: false, error: ack['message']?.toString() ?? 'Could not load messages.');
      }
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not load messages.');
    }
  }

  Future<void> loadOlder() async {
    if (state.loadingOlder || !state.hasMore || state.messages.isEmpty) return;
    state = state.copyWith(loadingOlder: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('chat:direct:history', {
        'peerId': _peerId,
        'before': state.messages.first.createdAt.toUtc().toIso8601String(),
      });
      final older = ack['ok'] == true ? _parse(ack['data']) : const <DirectMessage>[];
      state = state.copyWith(messages: _merge(older), loadingOlder: false, hasMore: older.length >= _page);
    } catch (_) {
      state = state.copyWith(loadingOlder: false);
    }
  }

  /// True when the server accepted the message.
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return false;
    state = state.copyWith(sending: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('chat:direct:send', {
        'commandId': _uuid.v4(),
        'toUserId': _peerId,
        'text': trimmed,
      });
      final data = ack['data'];
      if (ack['ok'] == true && data is Map) {
        state = state.copyWith(sending: false, messages: _merge([DirectMessage.fromJson(Map<String, dynamic>.from(data))]));
        return true;
      }
      state = state.copyWith(sending: false, error: ack['message']?.toString() ?? 'Message not sent.');
    } catch (_) {
      state = state.copyWith(sending: false, error: 'Message not sent. Check your connection.');
    }
    return false;
  }

  void _onEvent(RealtimeEvent event) {
    if (event.name != 'chat:direct:message') return;
    final me = ref.read(authControllerProvider).user?.id;
    if (me == null) return;
    final message = DirectMessage.fromJson(event.data);
    if (message.peerOf(me) != _peerId) return;
    state = state.copyWith(messages: _merge([message]));
    if (message.recipientId == me) unawaited(_markRead());
  }

  Future<void> _markRead() async {
    try {
      await ref.read(gameSocketServiceProvider).emitWithAck('chat:direct:read', {'peerId': _peerId});
    } catch (_) {}
  }

  /// Merge by id, oldest first (events, acks and history can overlap).
  List<DirectMessage> _merge(List<DirectMessage> incoming) {
    final byId = {for (final m in state.messages) m.id: m, for (final m in incoming) m.id: m};
    return byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<DirectMessage> _parse(Object? raw) => raw is List
      ? raw.whereType<Map>().map((item) => DirectMessage.fromJson(Map<String, dynamic>.from(item))).toList(growable: false)
      : const [];
}

final directChatControllerProvider =
    NotifierProvider.autoDispose.family<DirectChatController, DirectChatState, String>(DirectChatController.new);
