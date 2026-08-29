import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/game_hub/domain/game.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';

class GameHubRepository {
  GameHubRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> getMatch(String matchId) async {
    final response = await _api.request<Map<String, dynamic>>('/matches/$matchId');
    return response.data ?? const <String, dynamic>{};
  }

  Future<List<Game>> getGames() async {
    final response = await _api.request<dynamic>('/games');
    final raw = response.data;
    final items = raw is List
        ? raw
        : raw is Map
            ? [raw]
            : const [];
    return items
        .whereType<Map>()
        .map((item) => Game.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<List<GameMode>> getModes(String gameCode) async {
    final response = await _api.request<List<dynamic>>('/games/$gameCode/modes');
    return (response.data ?? const [])
        .whereType<Map>()
        .map((item) => GameMode.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}

final gameHubRepositoryProvider = Provider<GameHubRepository>((ref) {
  return GameHubRepository(ref.watch(apiClientProvider));
});
