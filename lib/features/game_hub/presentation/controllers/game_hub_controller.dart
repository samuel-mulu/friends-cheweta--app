import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';
import 'package:friends_game_app/features/game_hub/data/game_hub_repository.dart';
import 'package:friends_game_app/features/game_hub/domain/game.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';

class GameHubState {
  const GameHubState({
    this.games = const [],
    this.ludoModes = const [],
    this.loading = false,
    this.error,
  });

  final List<Game> games;
  final List<GameMode> ludoModes;
  final bool loading;
  final String? error;
}

class GameHubController extends Notifier<GameHubState> {
  @override
  GameHubState build() {
    Future.microtask(load);
    return const GameHubState(loading: true);
  }

  Future<void> load() async {
    state = GameHubState(
      games: state.games,
      ludoModes: state.ludoModes,
      loading: true,
    );
    try {
      final repository = ref.read(gameHubRepositoryProvider);
      final results = await Future.wait([
        repository.getGames(),
        repository.getModes('LUDO'),
      ]);
      state = GameHubState(
        games: results[0] as List<Game>,
        ludoModes: results[1] as List<GameMode>,
      );
    } on AppFailure catch (failure) {
      state = GameHubState(
        games: state.games,
        ludoModes: state.ludoModes,
        error: failure.message,
      );
    } catch (error) {
      state = GameHubState(
        games: state.games,
        ludoModes: state.ludoModes,
        error: error.toString().contains('OperationError')
            ? 'Session storage failed in the browser. Log out and sign in again.'
            : 'Could not load games right now.',
      );
    }
  }
}

final gameHubControllerProvider = NotifierProvider<GameHubController, GameHubState>(GameHubController.new);
