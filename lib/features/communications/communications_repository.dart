import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';

enum BroadcastMode { dismissible, persistent, forced }

class BroadcastNotice {
  const BroadcastNotice(
      {required this.id,
      required this.title,
      required this.body,
      required this.mode,
      required this.revision,
      required this.createdAt});

  factory BroadcastNotice.fromJson(Map<String, dynamic> json) =>
      BroadcastNotice(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        mode: BroadcastMode.values
            .byName((json['category'] as String).toLowerCase()),
        revision: json['revision'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  final String id;
  final String title;
  final String body;
  final BroadcastMode mode;
  final int revision;
  final DateTime createdAt;
  bool get canDismiss => mode == BroadcastMode.dismissible;
}

class BroadcastInbox {
  const BroadcastInbox(
      {required this.items,
      required this.unreadCount,
      required this.hasMore,
      this.forced,
      this.spotlight,
      this.matchPath});

  factory BroadcastInbox.fromJson(Map<String, dynamic> json) {
    final match = json['recoverableMatch'] as Map<String, dynamic>?;
    final code = match?['gameCode'];
    return BroadcastInbox(
      items: (json['items'] as List)
          .cast<Map<String, dynamic>>()
          .map(BroadcastNotice.fromJson)
          .toList(),
      unreadCount: json['unreadCount'] as int,
      hasMore: json['hasMore'] as bool,
      forced: json['forced'] == null
          ? null
          : BroadcastNotice.fromJson(json['forced'] as Map<String, dynamic>),
      spotlight: json['spotlight'] == null
          ? null
          : BroadcastNotice.fromJson(json['spotlight'] as Map<String, dynamic>),
      matchPath:
          const {GameCodes.ludo, GameCodes.dama, GameCodes.karta}.contains(code)
              ? GameRoutes.match(code as String, match!['id'] as String)
              : null,
    );
  }

  final List<BroadcastNotice> items;
  final int unreadCount;
  final bool hasMore;
  final BroadcastNotice? forced;
  final BroadcastNotice? spotlight;
  final String? matchPath;

  BroadcastInbox append(BroadcastInbox page) => BroadcastInbox(
        items: {
          for (final item in [...items, ...page.items]) item.id: item
        }.values.toList(),
        unreadCount: page.unreadCount,
        hasMore: page.hasMore,
        forced: page.forced,
        matchPath: page.matchPath,
      );
}

enum FeedbackCategory {
  feedback('Feedback'),
  complaint('Complaint'),
  advice('Advice'),
  other('Other');

  const FeedbackCategory(this.label);
  final String label;
}

class PlayerFeedback {
  const PlayerFeedback(
      {required this.id,
      required this.category,
      required this.status,
      required this.createdAt,
      this.message,
      this.reply,
      this.repliedAt,
      this.seen = false});

  factory PlayerFeedback.fromJson(Map<String, dynamic> json) => PlayerFeedback(
        id: json['id'] as String,
        category: FeedbackCategory.values
            .byName((json['category'] as String).toLowerCase()),
        status: switch (json['status']) {
          'OPEN' => 'Open',
          'REPLIED' => 'Replied',
          'CLOSED' => 'Closed',
          _ => 'Unknown'
        },
        createdAt: DateTime.parse(json['createdAt'] as String),
        message: json['message'] as String?,
        reply: json['adminReply'] as String?,
        repliedAt: DateTime.tryParse(json['repliedAt']?.toString() ?? ''),
        seen: json['playerSeenAt'] != null,
      );

  final String id;
  final FeedbackCategory category;
  final String status;
  final DateTime createdAt;
  final String? message;
  final String? reply;
  final DateTime? repliedAt;
  final bool seen;
}

class FeedbackInbox {
  const FeedbackInbox(
      {required this.items,
      required this.unreadCount,
      required this.hasMore,
      required this.seenThrough});

  factory FeedbackInbox.fromJson(Map<String, dynamic> json) => FeedbackInbox(
        items: (json['items'] as List)
            .cast<Map<String, dynamic>>()
            .map(PlayerFeedback.fromJson)
            .toList(),
        unreadCount: json['unreadCount'] as int,
        hasMore: json['hasMore'] as bool,
        seenThrough: json['seenThrough'] as String,
      );

  final List<PlayerFeedback> items;
  final int unreadCount;
  final bool hasMore;
  final String seenThrough;

  FeedbackInbox append(FeedbackInbox page) => FeedbackInbox(
        items: {
          for (final item in [...items, ...page.items]) item.id: item
        }.values.toList(),
        unreadCount: page.unreadCount,
        hasMore: page.hasMore,
        seenThrough: page.seenThrough,
      );
}

class CommunicationsRepository {
  CommunicationsRepository(this._api);
  final ApiClient _api;

  Future<BroadcastInbox> broadcasts({int page = 1, String? spotlightId}) async {
    final response = await _api.request<Map<String, dynamic>>(
        '/notifications/broadcasts',
        queryParameters: {
          'page': page,
          if (spotlightId != null) 'spotlightId': spotlightId
        });
    return BroadcastInbox.fromJson(response.data!);
  }

  Future<void> dismiss(BroadcastNotice notice) async {
    await _api.request<Map<String, dynamic>>(
        '/notifications/broadcasts/${notice.id}/dismiss',
        method: 'POST',
        data: {'revision': notice.revision});
  }

  Future<FeedbackInbox> feedback({int page = 1}) async {
    final response = await _api.request<Map<String, dynamic>>(
        '/support/messages/me',
        queryParameters: {'page': page});
    return FeedbackInbox.fromJson(response.data!);
  }

  Future<void> send(
      FeedbackCategory category, String message, String requestId) async {
    await _api.request<Map<String, dynamic>>('/support/messages',
        method: 'POST',
        data: {
          'category': category.name.toUpperCase(),
          'message': message,
          'requestId': requestId
        });
  }

  Future<void> markSeen(String seenThrough) async {
    await _api.request<Map<String, dynamic>>('/support/messages/me/mark-seen',
        method: 'POST', data: {'seenThrough': seenThrough});
  }
}

final communicationsRepositoryProvider = Provider<CommunicationsRepository>(
    (ref) => CommunicationsRepository(ref.watch(apiClientProvider)));
