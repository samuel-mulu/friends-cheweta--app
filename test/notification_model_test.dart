import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/notifications/domain/app_notification.dart';

void main() {
  test('unread notification becomes readable from backend contract', () {
    final item = AppNotification.fromJson({
      'id': 'n1',
      'type': 'MATCH_RESULT',
      'title': 'Match settled',
      'message': 'Your prize is ready.',
      'createdAt': '2026-08-24T10:00:00.000Z',
      'readAt': null,
      'data': {'matchId': 'm1'},
    });
    expect(item.isRead, false);
    expect(item.data?['matchId'], 'm1');
  });
}
