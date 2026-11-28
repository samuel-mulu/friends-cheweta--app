import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/karta/domain/karta_table.dart';

/// The Karta queue table I sit at, live from the server.
class KartaTableViewState {
  const KartaTableViewState({this.table, this.loading = false, this.busy = false, this.error, this.endedReason});

  final KartaTable? table;
  final bool loading;
  final bool busy;
  final String? error;

  /// Set when I am no longer at the table (closed, removed, or I left): why.
  final String? endedReason;

  KartaTableViewState copyWith({
    KartaTable? table,
    bool? loading,
    bool? busy,
    String? error,
    bool clearError = false,
    String? endedReason,
  }) =>
      KartaTableViewState(
        table: table ?? this.table,
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
        error: clearError ? null : error ?? this.error,
        endedReason: endedReason ?? this.endedReason,
      );
}

class KartaTableController extends Notifier<KartaTableViewState> {
  StreamSubscription<RealtimeEvent>? _events;
  StreamSubscription<GameSocketStatus>? _statuses;

  @override
  KartaTableViewState build() {
    final socket = ref.watch(gameSocketServiceProvider);
    _events?.cancel();
    _statuses?.cancel();
    _events = socket.events.listen(_onEvent);
    _statuses = socket.statuses.listen((status) {
      if (status == GameSocketStatus.connected && state.table != null) unawaited(load());
    });
    ref.onDispose(() {
      _events?.cancel();
      _statuses?.cancel();
    });
    return const KartaTableViewState();
  }

  /// The table I sit at (after opening the screen, a reconnect or a resume).
  Future<void> load() async {
    state = state.copyWith(loading: state.table == null, clearError: true);
    try {
      final socket = ref.read(gameSocketServiceProvider);
      if (!socket.isConnected) await socket.connect();
      final ack = await socket.emitWithAck('karta:table:mine', const {});
      final data = ack['data'];
      if (ack['ok'] != true) {
        state = state.copyWith(loading: false, error: ack['message']?.toString() ?? 'Could not open the table.');
      } else if (data is Map) {
        state = KartaTableViewState(table: KartaTable.fromJson(Map<String, dynamic>.from(data)));
      } else {
        state = state.copyWith(loading: false, endedReason: 'CLOSED');
      }
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not open the table. Check your connection.');
    }
  }

  /// Leave the table (in a round: that round is lost).
  Future<bool> leave() => _send('karta:table:leave', const {}, ended: 'LEFT');

  /// Ask the other player of this round to raise the stake from the next round.
  Future<bool> raise(int amountMinor) => _send('karta:table:raise', {'amountMinor': amountMinor});

  Future<bool> answerRaise(bool accept) => _send('karta:table:raise_answer', {'accept': accept});

  Future<bool> _send(String event, Map<String, dynamic> payload, {String? ended}) async {
    if (state.busy) return false;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final ack = await ref.read(gameSocketServiceProvider).emitWithAck(event, payload);
      final data = ack['data'];
      if (ack['ok'] == true) {
        state = state.copyWith(
          busy: false,
          table: data is Map ? KartaTable.fromJson(Map<String, dynamic>.from(data)) : null,
          endedReason: ended,
        );
        return true;
      }
      state = state.copyWith(busy: false, error: tableErrorText(ack['code']?.toString(), ack['message']?.toString()));
    } catch (_) {
      state = state.copyWith(busy: false, error: 'Slow connection. Try again.');
    }
    return false;
  }

  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }

  void _onEvent(RealtimeEvent event) {
    final data = event.data;
    final current = state.table;
    switch (event.name) {
      case 'karta:table:state':
        final table = KartaTable.fromJson(data);
        if (current == null || table.id == current.id) state = state.copyWith(table: table, loading: false);
      case 'karta:table:removed':
        if (current == null || data['tableId'] == current.id) state = state.copyWith(endedReason: data['reason']?.toString() ?? 'REMOVED');
      case 'karta:table:closed':
        if (current == null || data['tableId'] == current.id) state = state.copyWith(endedReason: 'CLOSED');
    }
  }
}

/// Why the table ended for me, in words.
String tableEndedText(String reason) => switch (reason) {
      'INSUFFICIENT_BALANCE' => 'You left the table: your balance is below the stake.',
      'OFFLINE' => 'You left the table because you were offline.',
      'LEFT' => 'You left the table.',
      _ => 'The table has closed: not enough players.',
    };

String tableErrorText(String? code, String? fallback) => switch (code) {
      'TABLE_NOT_IN_ROUND' => 'Only the two players of this round can raise the stake.',
      'TABLE_RAISE_INVALID' => 'Choose one of the higher stakes.',
      'TABLE_NO_RAISE' => 'That raise is no longer open.',
      'TABLE_NOT_FOUND' => 'This table has closed.',
      _ => fallback ?? 'Something went wrong. Try again.',
    };

final kartaTableControllerProvider = NotifierProvider<KartaTableController, KartaTableViewState>(KartaTableController.new);
