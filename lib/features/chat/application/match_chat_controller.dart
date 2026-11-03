import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/chat/domain/chat_message.dart';

class MatchChatState {
  const MatchChatState({
    this.matchId,
    this.messages = const [],
    this.sending = false,
    this.loading = false,
    this.error,
    this.unread = 0,
    this.panelOpen = false,
  });

  final String? matchId;
  final List<ChatMessage> messages;
  final bool sending;
  final bool loading;
  final String? error;
  final int unread;
  final bool panelOpen;

  MatchChatState copyWith({
    String? matchId,
    List<ChatMessage>? messages,
    bool? sending,
    bool? loading,
    String? error,
    bool clearError = false,
    int? unread,
    bool? panelOpen,
  }) =>
      MatchChatState(
        matchId: matchId ?? this.matchId,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
        unread: unread ?? this.unread,
        panelOpen: panelOpen ?? this.panelOpen,
      );
}

class MatchChatController extends Notifier<MatchChatState> {
  final _uuid = const Uuid();
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<GameSocketStatus>? _statuses;

  @override
  MatchChatState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    _events?.cancel();
    _statuses?.cancel();
    _events = socket.events.listen(_onEvent);
    _statuses = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected && state.matchId != null) unawaited(load(state.matchId!));
    });
    ref.onDispose(() {
      _events?.cancel();
      _statuses?.cancel();
    });
    return const MatchChatState();
  }

  Future<void> load(String matchId) async {
    if (state.matchId == matchId && state.messages.isNotEmpty) return;
    state = state.copyWith(matchId: matchId, loading: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('match:chat:history', {'matchId': matchId});
      if (ack['ok'] == true) {
        state = state.copyWith(messages: _parseMessages(ack['messages']), loading: false, unread: 0);
      } else {
        state = state.copyWith(loading: false, error: _message(ack));
      }
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not load match chat.');
    }
  }

  Future<void> send(String text) async {
    final matchId = state.matchId;
    final trimmed = text.trim();
    if (matchId == null || trimmed.isEmpty || trimmed.length > 160 || state.sending) return;
    state = state.copyWith(sending: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck('match:chat:send', {
        'commandId': _uuid.v4(),
        'matchId': matchId,
        'text': trimmed,
      });
      state = state.copyWith(sending: false, error: ack['ok'] == true ? null : _message(ack), clearError: ack['ok'] == true);
    } catch (_) {
      state = state.copyWith(sending: false, error: 'Could not send message.');
    }
  }

  void setPanelOpen(bool open) {
    state = state.copyWith(panelOpen: open, unread: open ? 0 : state.unread);
  }

  void _onEvent(RealtimeEvent event) {
    if (event.name != 'match:chat:message' || event.matchId != state.matchId) return;
    final message = ChatMessage.fromJson(event.data);
    if (message.id.isEmpty || state.messages.any((item) => item.id == message.id)) return;
    final next = [...state.messages, message];
    state = state.copyWith(
      messages: next.length > 50 ? next.sublist(next.length - 50) : next,
      sending: false,
      unread: state.panelOpen ? 0 : state.unread + 1,
      clearError: true,
    );
  }

  List<ChatMessage> _parseMessages(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item))).toList(growable: false);
  }

  String _message(Map<String, dynamic> ack) => ack['message']?.toString() ?? ack['code']?.toString() ?? 'Chat request failed.';
}

final matchChatControllerProvider = NotifierProvider<MatchChatController, MatchChatState>(MatchChatController.new);
