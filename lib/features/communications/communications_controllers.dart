import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/communications/communications_repository.dart';

final communicationsPlayerProvider = Provider<String?>((ref) {
  final user = ref.watch(authControllerProvider.select((state) => state.user));
  return user?.role == 'PLAYER' ? user?.id : null;
});

typedef BroadcastSpotlight = ({String id, int revision});

class BroadcastState {
  const BroadcastState(
      {this.inbox, this.banner, this.error, this.loading = false});
  final BroadcastInbox? inbox;
  final BroadcastNotice? banner;
  final String? error;
  final bool loading;
}

class BroadcastController extends Notifier<BroadcastState> {
  int _generation = 0;
  int _page = 1;
  BroadcastSpotlight? _pendingSpotlight;
  Timer? _bannerTimer;
  final _presented = <BroadcastSpotlight>{};

  @override
  BroadcastState build() {
    final player = ref.watch(communicationsPlayerProvider);
    _generation++;
    _page = 1;
    _pendingSpotlight = null;
    _presented.clear();
    _bannerTimer?.cancel();
    ref.onDispose(() {
      _generation++;
      _bannerTimer?.cancel();
    });
    if (player != null) {
      final generation = _generation;
      Future.microtask(() {
        if (generation == _generation) unawaited(refresh());
      });
    }
    return BroadcastState(loading: player != null);
  }

  Future<void> refresh({BroadcastSpotlight? spotlight}) async {
    if (ref.read(communicationsPlayerProvider) == null) return;
    if (spotlight != null && !_presented.contains(spotlight)) {
      _pendingSpotlight = spotlight;
    }
    final target = _pendingSpotlight;
    final generation = ++_generation;
    if (state.inbox == null) state = const BroadcastState(loading: true);
    try {
      final inbox = await ref
          .read(communicationsRepositoryProvider)
          .broadcasts(spotlightId: target?.id);
      if (generation != _generation) return;
      _page = 1;
      _pendingSpotlight = null;
      final next = inbox.spotlight;
      final currentBanner = state.banner;
      final display = inbox.forced == null &&
          target != null &&
          next?.revision == target.revision;
      state = BroadcastState(
          inbox: inbox,
          banner: inbox.forced != null
              ? null
              : display
                  ? next
                  : inbox.items.any((item) =>
                          item.id == currentBanner?.id &&
                          item.revision == currentBanner?.revision)
                      ? currentBanner
                      : null);
      if (display) {
        if (_presented.length >= 100) _presented.remove(_presented.first);
        _presented.add(target);
        _bannerTimer?.cancel();
        _bannerTimer = Timer(const Duration(seconds: 10), hideBanner);
      }
    } on AppFailure catch (error) {
      if (generation != _generation) return;
      _pendingSpotlight = null;
      state = BroadcastState(inbox: state.inbox, error: error.message);
    }
  }

  Future<void> loadMore() async {
    final inbox = state.inbox;
    if (state.loading || inbox == null || !inbox.hasMore) return;
    final generation = ++_generation;
    state = BroadcastState(inbox: inbox, loading: true, banner: state.banner);
    try {
      final next = await ref
          .read(communicationsRepositoryProvider)
          .broadcasts(page: _page + 1);
      if (generation != _generation) return;
      _page++;
      state = BroadcastState(
          inbox: inbox.append(next),
          banner: next.forced == null ? state.banner : null);
    } on AppFailure catch (error) {
      if (generation == _generation) {
        state = BroadcastState(
            inbox: inbox, banner: state.banner, error: error.message);
      }
    }
  }

  void hideBanner() {
    _bannerTimer?.cancel();
    if (state.banner == null) return;
    state = BroadcastState(
        inbox: state.inbox, error: state.error, loading: state.loading);
  }

  Future<void> dismiss(BroadcastNotice notice) async {
    final player = ref.read(communicationsPlayerProvider);
    try {
      await ref.read(communicationsRepositoryProvider).dismiss(notice);
    } finally {
      if (ref.read(communicationsPlayerProvider) == player) await refresh();
    }
  }
}

class FeedbackState {
  const FeedbackState({this.inbox, this.error, this.loading = false});
  final FeedbackInbox? inbox;
  final String? error;
  final bool loading;
}

class FeedbackController extends Notifier<FeedbackState> {
  int _generation = 0;
  int _page = 1;

  @override
  FeedbackState build() {
    final player = ref.watch(communicationsPlayerProvider);
    final generation = ++_generation;
    _page = 1;
    ref.onDispose(() => _generation++);
    if (player != null) {
      Future.microtask(() {
        if (generation == _generation) unawaited(refresh());
      });
    }
    return FeedbackState(loading: player != null);
  }

  Future<void> refresh() => _load(false);
  Future<void> loadMore() => _load(true);

  Future<void> _load(bool more) async {
    final current = state.inbox;
    if (ref.read(communicationsPlayerProvider) == null ||
        (more && (state.loading || current?.hasMore != true))) {
      return;
    }
    final generation = ++_generation;
    final page = more ? _page + 1 : 1;
    state = FeedbackState(inbox: current, loading: true);
    try {
      final next =
          await ref.read(communicationsRepositoryProvider).feedback(page: page);
      if (generation != _generation) return;
      _page = page;
      state = FeedbackState(inbox: more ? current!.append(next) : next);
    } on AppFailure catch (error) {
      if (generation == _generation) {
        state = FeedbackState(inbox: current, error: error.message);
      }
    }
  }

  Future<void> markSeen(String cutoff) async {
    final player = ref.read(communicationsPlayerProvider);
    await ref.read(communicationsRepositoryProvider).markSeen(cutoff);
    if (ref.read(communicationsPlayerProvider) == player) await refresh();
  }

  Future<void> send(
      FeedbackCategory category, String message, String requestId) async {
    final player = ref.read(communicationsPlayerProvider);
    await ref
        .read(communicationsRepositoryProvider)
        .send(category, message, requestId);
    if (ref.read(communicationsPlayerProvider) == player) await refresh();
  }
}

final broadcastControllerProvider =
    NotifierProvider<BroadcastController, BroadcastState>(
        BroadcastController.new);
final feedbackControllerProvider =
    NotifierProvider<FeedbackController, FeedbackState>(FeedbackController.new);

final communicationsUnreadProvider = Provider<int>((ref) =>
    ref.watch(broadcastControllerProvider
        .select((state) => state.inbox?.unreadCount ?? 0)) +
    ref.watch(feedbackControllerProvider
        .select((state) => state.inbox?.unreadCount ?? 0)));
