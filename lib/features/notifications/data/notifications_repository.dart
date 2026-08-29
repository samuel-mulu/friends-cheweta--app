import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/notifications/domain/app_notification.dart';

class NotificationPage {
  const NotificationPage({required this.items, required this.unreadCount});
  final List<AppNotification> items;
  final int unreadCount;
}

class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  Future<NotificationPage> list({int limit = 30, bool unreadOnly = false}) async {
    final response = await _api.request<Map<String, dynamic>>('/notifications', queryParameters: {'limit': limit, 'unreadOnly': unreadOnly});
    final data = response.data ?? const {};
    return NotificationPage(
      items: (data['items'] as List? ?? const []).whereType<Map>().map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e))).toList(),
      unreadCount: int.tryParse(data['unreadCount']?.toString() ?? '') ?? 0,
    );
  }

  Future<void> markRead(String id) => _api.request('/notifications/$id/read', method: 'PATCH').then((_) {});
  Future<void> markAllRead() => _api.request('/notifications/read-all', method: 'PATCH').then((_) {});
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) => NotificationsRepository(ref.watch(apiClientProvider)));
