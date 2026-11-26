import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/communications/communications_repository.dart';

class EmptyCommunications extends Fake implements CommunicationsRepository {
  @override
  Future<BroadcastInbox> broadcasts(
          {int page = 1, String? spotlightId}) async =>
      const BroadcastInbox(items: [], unreadCount: 0, hasMore: false);

  @override
  Future<FeedbackInbox> feedback({int page = 1}) async => const FeedbackInbox(
        items: [],
        unreadCount: 0,
        hasMore: false,
        seenThrough: '0',
      );
}
