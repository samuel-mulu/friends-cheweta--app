import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/features/history/data/match_history_repository.dart';
import 'package:friends_game_app/features/history/domain/match_history.dart';

class MatchHistoryState {
  const MatchHistoryState({this.items = const [], this.loading = false, this.loadingMore = false, this.nextCursor, this.error});
  final List<MatchHistoryItem> items;
  final bool loading;
  final bool loadingMore;
  final String? nextCursor;
  final String? error;

  MatchHistoryState copyWith({List<MatchHistoryItem>? items, bool? loading, bool? loadingMore, String? nextCursor, bool clearCursor = false, String? error, bool clearError = false}) => MatchHistoryState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
        error: clearError ? null : error ?? this.error,
      );
}

class MatchHistoryController extends Notifier<MatchHistoryState> {
  @override
  MatchHistoryState build() {
    Future.microtask(load);
    return const MatchHistoryState(loading: true);
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true, clearCursor: true);
    try {
      final page = await ref.read(matchHistoryRepositoryProvider).mine();
      state = MatchHistoryState(items: page.items, nextCursor: page.nextCursor);
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Could not load your match history.');
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (cursor == null || state.loadingMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref.read(matchHistoryRepositoryProvider).mine(cursor: cursor);
      state = MatchHistoryState(items: [...state.items, ...page.items], nextCursor: page.nextCursor);
    } catch (_) {
      state = state.copyWith(loadingMore: false, error: 'Could not load more matches.');
    }
  }
}

final matchHistoryControllerProvider = NotifierProvider<MatchHistoryController, MatchHistoryState>(MatchHistoryController.new);

final matchDetailProvider = FutureProvider.family<MatchHistoryItem, String>((ref, id) => ref.watch(matchHistoryRepositoryProvider).getMatch(id));
final matchReplayProvider = FutureProvider.family<MatchReplay, String>((ref, id) => ref.watch(matchHistoryRepositoryProvider).replay(id));
