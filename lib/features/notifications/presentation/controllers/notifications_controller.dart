import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/features/notifications/data/notifications_repository.dart';
import 'package:friends_game_app/features/notifications/domain/app_notification.dart';

class NotificationsState {
  const NotificationsState({this.items = const [], this.unreadCount = 0, this.loading = false, this.error});
  final List<AppNotification> items;
  final int unreadCount;
  final bool loading;
  final String? error;
}

class NotificationsController extends Notifier<NotificationsState> {
  @override
  NotificationsState build() {
    Future.microtask(load);
    return const NotificationsState(loading: true);
  }

  Future<void> load() async {
    state = NotificationsState(items: state.items, unreadCount: state.unreadCount, loading: true);
    try {
      final page = await ref.read(notificationsRepositoryProvider).list();
      state = NotificationsState(items: page.items, unreadCount: page.unreadCount);
    } catch (_) {
      state = NotificationsState(items: state.items, unreadCount: state.unreadCount, error: 'Could not load notifications.');
    }
  }

  Future<void> markRead(String id) async {
    final index = state.items.indexWhere((e) => e.id == id);
    if (index < 0 || state.items[index].isRead) return;
    try {
      await ref.read(notificationsRepositoryProvider).markRead(id);
      final now = DateTime.now();
      final updated = [...state.items];
      final old = updated[index];
      updated[index] = AppNotification(id: old.id, type: old.type, title: old.title, message: old.message, createdAt: old.createdAt, readAt: now, data: old.data);
      state = NotificationsState(items: updated, unreadCount: (state.unreadCount - 1).clamp(0, 1 << 30).toInt());
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
      final now = DateTime.now();
      state = NotificationsState(
        unreadCount: 0,
        items: state.items.map((e) => e.isRead ? e : AppNotification(id: e.id, type: e.type, title: e.title, message: e.message, createdAt: e.createdAt, readAt: now, data: e.data)).toList(),
      );
    } catch (_) {}
  }
}

final notificationsControllerProvider = NotifierProvider<NotificationsController, NotificationsState>(NotificationsController.new);
