import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/history/domain/match_history.dart';

class MatchHistoryPage {
  const MatchHistoryPage({required this.items, this.nextCursor});
  final List<MatchHistoryItem> items;
  final String? nextCursor;
}

class MatchHistoryRepository {
  MatchHistoryRepository(this._api);
  final ApiClient _api;

  Future<MatchHistoryPage> mine({int limit = 20, String? cursor}) async {
    final response = await _api.request<Map<String, dynamic>>('/matches/me', queryParameters: {
      'limit': limit,
      if (cursor != null) 'cursor': cursor,
    });
    final data = response.data ?? const {};
    return MatchHistoryPage(
      items: (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => MatchHistoryItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      nextCursor: data['nextCursor']?.toString(),
    );
  }

  Future<MatchHistoryItem> getMatch(String id) async {
    final response = await _api.request<Map<String, dynamic>>('/matches/$id');
    return MatchHistoryItem.fromJson(response.data ?? const {});
  }

  Future<MatchReplay> replay(String id) async {
    final response = await _api.request<Map<String, dynamic>>('/matches/$id/replay');
    return MatchReplay.fromJson(response.data ?? const {});
  }
}

final matchHistoryRepositoryProvider = Provider<MatchHistoryRepository>((ref) => MatchHistoryRepository(ref.watch(apiClientProvider)));
