import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/domain/direct_message.dart';

class ChatInboxState {
  const ChatInboxState({this.conversations = const [], this.loading = false, this.error, this.openPeerId});

  final List<Conversation> conversations;
  final bool loading;
  final String? error;

  /// The conversation currently on screen (its messages count as read).
  final String? openPeerId;

  int get unreadTotal => conversations.fold(0, (sum, c) => sum + c.unread);

  ChatInboxState copyWith({List<Conversation>? conversations, bool? loading, String? error, bool clearError = false, String? openPeerId, bool clearOpen = false}) =>
      ChatInboxState(
        conversations: conversations ?? this.conversations,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
        openPeerId: clearOpen ? null : openPeerId ?? this.openPeerId,
      );
}

/// App-wide private-message inbox: conversation list + unread badge. Live
/// via `chat:direct:message`; re-synced from the server on every reconnect.
class ChatInboxController extends Notifier<ChatInboxState> {
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<GameSocketStatus>? _statuses;

  @override
  ChatInboxState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    _events?.cancel();
    _statuses?.cancel();
    _events = socket.events.listen(_onEvent);
    _statuses = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected) unawaited(refresh());
    });
    ref.onDispose(() {
      _events?.cancel();
      _statuses?.cancel();
    });
    if (socket.isConnected) Future.microtask(refresh);
    return const ChatInboxState();
  }

  String? get _me => ref.read(authControllerProvider).user?.id;

  Future<void> refresh() async {
    if (_me == null) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('chat:conversations');
      final data = ack['data'];
      if (ack['ok'] == true && data is Map) {
        final list = (data['conversations'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => Conversation.fromJson(Map<String, dynamic>.from(item)))
            .map((c) => c.peerId == state.openPeerId ? c.copyWith(unread: 0) : c)
            .toList(growable: false);
        state = state.copyWith(conversations: list, loading: false);
      } else {
        state = state.copyWith(loading: false, error: ack['message']?.toString() ?? 'Could not load messages.');
      }
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not load messages.');
    }
  }

  void setOpen(String? peerId) {
    state = peerId == null
        ? state.copyWith(clearOpen: true)
        : state.copyWith(
            openPeerId: peerId,
            conversations: [for (final c in state.conversations) c.peerId == peerId ? c.copyWith(unread: 0) : c],
          );
  }

  /// Clears the open conversation only if it is still [peerId] (another chat
  /// may have opened in the meantime).
  void close(String peerId) {
    if (state.openPeerId == peerId) state = state.copyWith(clearOpen: true);
  }

  void _onEvent(RealtimeEvent event) {
    final me = _me;
    if (me == null) return;
    if (event.name == 'chat:direct:read') {
      final peerId = event.data['peerId']?.toString();
      state = state.copyWith(conversations: [for (final c in state.conversations) c.peerId == peerId ? c.copyWith(unread: 0) : c]);
      return;
    }
    if (event.name != 'chat:direct:message') return;
    final message = DirectMessage.fromJson(event.data);
    final peerId = message.peerOf(me);
    final incoming = message.recipientId == me;
    final existing = state.conversations.where((c) => c.peerId == peerId).firstOrNull;
    if (existing == null) {
      if (!incoming) {
        unawaited(refresh()); // first message to a new peer: fetch the name from the server
        return;
      }
      final created = Conversation(peerId: peerId, peerName: message.senderName, lastMessage: message, unread: 0);
      state = state.copyWith(conversations: [_bump(created, incoming, peerId), ...state.conversations]);
      return;
    }
    if (existing.lastMessage.id == message.id) return;
    state = state.copyWith(conversations: [
      _bump(existing.copyWith(lastMessage: message), incoming, peerId),
      ...state.conversations.where((c) => c.peerId != peerId),
    ]);
  }

  Conversation _bump(Conversation c, bool incoming, String peerId) =>
      incoming && state.openPeerId != peerId ? c.copyWith(unread: c.unread + 1) : c;
}

final chatInboxControllerProvider = NotifierProvider<ChatInboxController, ChatInboxState>(ChatInboxController.new);
