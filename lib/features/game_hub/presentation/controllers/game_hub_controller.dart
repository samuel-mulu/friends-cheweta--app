import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/core/storage/json_cache.dart';
import 'package:friends_game_app/features/game_hub/data/game_hub_repository.dart';
import 'package:friends_game_app/features/game_hub/domain/game.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';

/// Games with a live lobby, in hub order.
const liveGameCodes = [GameCodes.ludo, GameCodes.karta, GameCodes.dama];

/// Games with practice against the computer.
const practiceGameCodes = {GameCodes.ludo, GameCodes.dama};

class GameHubState {
  const GameHubState({
    this.games = const [],
    this.modesByGame = const {},
    this.loading = false,
    this.error,
  });

  final List<Game> games;
  final Map<String, List<GameMode>> modesByGame;
  final bool loading;
  final String? error;

  List<GameMode> modesFor(String gameCode) => modesByGame[gameCode] ?? const [];
  List<GameMode> get ludoModes => modesFor(GameCodes.ludo);
}

class GameHubController extends Notifier<GameHubState> {
  static const _cacheKey = 'game_modes';

  @override
  GameHubState build() {
    Future.microtask(load);
    // Rooms from the last visit show at once; the server's answer replaces them.
    return GameHubState(modesByGame: _cached(), loading: true);
  }

  Map<String, List<GameMode>> _cached() {
    final raw = ref.read(jsonCacheProvider).read(_cacheKey);
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is List)
          entry.key.toString(): [
            for (final item in entry.value as List)
              if (item is Map) GameMode.fromJson(Map<String, dynamic>.from(item)).withGameCode(entry.key.toString()),
          ],
    };
  }

  Future<void> load() async {
    state = GameHubState(games: state.games, modesByGame: state.modesByGame, loading: true);
    try {
      final repository = ref.read(gameHubRepositoryProvider);
      final games = repository.getGames();
      // Ludo must load; another game's catalog missing (older server) just shows no rooms.
      final ludo = repository.getModes(GameCodes.ludo);
      final others = [
        for (final code in liveGameCodes.where((code) => code != GameCodes.ludo))
          repository.getModes(code).then((modes) => MapEntry(code, modes)).catchError((_) => MapEntry(code, <GameMode>[])),
      ];
      final results = await Future.wait([games, ludo, Future.wait(others)]);
      state = GameHubState(
        games: results[0] as List<Game>,
        modesByGame: {
          GameCodes.ludo: results[1] as List<GameMode>,
          for (final entry in results[2] as List<MapEntry<String, List<GameMode>>>) entry.key: entry.value,
        },
      );
      await ref.read(jsonCacheProvider).write(_cacheKey, {
        for (final entry in state.modesByGame.entries) entry.key: [for (final mode in entry.value) mode.toJson()],
      });
    } on AppFailure catch (failure) {
      state = GameHubState(games: state.games, modesByGame: state.modesByGame, error: failure.message);
    } catch (error) {
      state = GameHubState(
        games: state.games,
        modesByGame: state.modesByGame,
        error: error.toString().contains('OperationError')
            ? 'Session storage failed in the browser. Log out and sign in again.'
            : 'Could not load games right now.',
      );
    }
  }
}

final gameHubControllerProvider = NotifierProvider<GameHubController, GameHubState>(GameHubController.new);
