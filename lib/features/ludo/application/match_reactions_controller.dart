import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';

/// Quick phrases and emojis (ids match the server whitelist).
enum MatchReaction {
  goodLuck('good_luck', 'Good luck!'),
  niceMove('nice_move', 'Nice move!'),
  hurryUp('hurry_up', 'Hurry up 😅'),
  oops('oops', 'Oops!'),
  thanks('thanks', 'Thanks!'),
  gg('gg', 'GG'),
  thumbsUp('thumbs_up', '👍'),
  laugh('laugh', '😂'),
  angry('angry', '😡'),
  wow('wow', '😮'),
  party('party', '🎉'),
  pray('pray', '🙏');

  const MatchReaction(this.id, this.display);
  final String id;
  final String display;

  bool get isEmoji => index >= MatchReaction.thumbsUp.index;

  static MatchReaction? byId(String? id) => MatchReaction.values.where((r) => r.id == id).firstOrNull;
}

class ShownReaction {
  const ShownReaction(this.reaction, this.seq);
  final MatchReaction reaction;

  /// Changes for every new reaction so the bubble re-animates.
  final int seq;
}

/// Latest reaction per player in the current match, visible for a moment.
class MatchReactionsController extends Notifier<Map<String, ShownReaction>> {
  static const visibleFor = Duration(milliseconds: 2500);
  StreamSubscription<RealtimeEvent>? _events;
  final Map<String, Timer> _timers = {};
  String? _matchId;
  int _seq = 0;

  @override
  Map<String, ShownReaction> build() {
    final socket = ref.watch(gameSocketServiceProvider);
    _events?.cancel();
    _events = socket.events.listen(_onEvent);
    ref.onDispose(() {
      _events?.cancel();
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return const {};
  }

  void attach(String matchId) {
    if (_matchId == matchId) return;
    _matchId = matchId;
    state = const {};
  }

  /// Sends a reaction; failures (e.g. too fast) are ignored on purpose.
  Future<void> send(MatchReaction reaction) async {
    final matchId = _matchId;
    if (matchId == null) return;
    try {
      await ref.read(gameSocketServiceProvider).emitWithAck('match:reaction', {'matchId': matchId, 'reactionId': reaction.id});
    } catch (_) {}
  }

  void _onEvent(RealtimeEvent event) {
    if (event.name != 'match:reaction' || event.matchId == null || event.matchId != _matchId) return;
    final userId = event.data['userId']?.toString();
    final reaction = MatchReaction.byId(event.data['reactionId']?.toString());
    if (userId == null || reaction == null) return;
    state = {...state, userId: ShownReaction(reaction, ++_seq)};
    _timers[userId]?.cancel();
    _timers[userId] = Timer(visibleFor, () {
      state = {...state}..remove(userId);
    });
  }
}

final matchReactionsProvider = NotifierProvider<MatchReactionsController, Map<String, ShownReaction>>(MatchReactionsController.new);
