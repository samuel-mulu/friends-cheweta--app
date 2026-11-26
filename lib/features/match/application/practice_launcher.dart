import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_type_picker.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/goal_picker.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

/// Free practice against the computer (server-run bot, no stake).
enum PracticeLevel {
  easy('EASY', 'Easy', 'Relaxed bot that moves at random.', Icons.sentiment_satisfied_alt_rounded),
  normal('NORMAL', 'Normal', 'Goes for captures whenever it can.', Icons.sports_esports_rounded),
  hard('HARD', 'Hard', 'Plays safe, hunts and escapes like a pro.', Icons.local_fire_department_rounded);

  const PracticeLevel(this.code, this.label, this.description, this.icon);
  final String code;
  final String label;
  final String description;
  final IconData icon;

  /// How this bot plays in [gameCode].
  String describe(String gameCode) => gameCode == GameCodes.dama
      ? switch (this) {
          PracticeLevel.easy => 'Relaxed bot that moves at random.',
          PracticeLevel.normal => 'Looks a move ahead and punishes loose pieces.',
          PracticeLevel.hard => 'Reads several moves deep. Bring your best.',
        }
      : description;
}

typedef PracticeStart = ({String matchId, String gameCode});

/// Last level chosen this session (for "Play again" on the result screen).
final lastPracticeLevelProvider = StateProvider<PracticeLevel?>((ref) => null);

class PracticeLauncher {
  PracticeLauncher(this._ref);
  final Ref _ref;
  static const _uuid = Uuid();

  /// Starts (or resumes) a practice game. A resumed game may be another game
  /// than [gameCode]; the result says which screen to open.
  /// [damaType] picks the Dama rules (እግረኛ / ታንከኛ).
  Future<PracticeStart> start(
    PracticeLevel level, {
    int tokensToWin = 4,
    String gameCode = GameCodes.ludo,
    DamaType? damaType,
  }) async {
    final ack = await _ref.read(gameSocketServiceProvider).emitWithAck('practice:start', {
      'commandId': _uuid.v4(),
      'level': level.code,
      if (gameCode == GameCodes.ludo) 'tokensToWin': tokensToWin,
      if (gameCode != GameCodes.ludo) 'game': gameCode,
      if (gameCode == GameCodes.dama && damaType != null) 'rulesVersion': damaType.rulesVersion,
    });
    final data = ack['data'];
    final matchId = ack['ok'] == true && data is Map ? data['matchId']?.toString() : null;
    if (matchId == null || matchId.isEmpty) {
      throw PracticeStartException(switch (ack['code']?.toString()) {
        'LOBBY_ACTIVE_MATCH' => 'Finish your current match first.',
        'PRACTICE_UNAVAILABLE' => 'Practice is not available right now.',
        _ => ack['message']?.toString() ?? 'Could not start practice.',
      });
    }
    _ref.read(lastPracticeLevelProvider.notifier).state = level;
    return (matchId: matchId, gameCode: (data as Map)['gameCode']?.toString() ?? gameCode);
  }
}

class PracticeStartException implements Exception {
  const PracticeStartException(this.message);
  final String message;
  @override
  String toString() => message;
}

final practiceLauncherProvider = Provider<PracticeLauncher>(PracticeLauncher.new);

/// Level picker → start → open the match. Shared by the game lobbies and result screens.
Future<void> showPracticeSheet(BuildContext context, WidgetRef ref, {String gameCode = GameCodes.ludo}) async {
  // Dama: pick the type first (opens on the one played last).
  var damaType = ref.read(playerPreferencesProvider).damaType;
  final level = await showModalBottomSheet<PracticeLevel>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Practice vs computer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Free. Does not count for stats or the leaderboard.'),
            ),
            if (gameCode == GameCodes.dama)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: DamaTypePicker(selected: damaType, onChanged: (type) => setSheet(() => damaType = type)),
              ),
            for (final level in PracticeLevel.values)
              ListTile(
                leading: Icon(level.icon),
                title: Text(level.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(level.describe(gameCode)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, level),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  if (level == null || !context.mounted) return;
  if (gameCode == GameCodes.dama) await ref.read(playerPreferencesProvider.notifier).setDamaType(damaType);
  if (!context.mounted) return;
  if (gameCode == GameCodes.ludo) {
    final goal = await pickGoal(context, confirmLabel: 'Start');
    if (goal == null || !context.mounted) return;
  }
  await startPractice(context, ref, level, gameCode: gameCode);
}

Future<void> startPractice(BuildContext context, WidgetRef ref, PracticeLevel level, {String gameCode = GameCodes.ludo}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    // "Play again" reuses the last goal (Ludo) or type (Dama) chosen.
    final prefs = ref.read(playerPreferencesProvider);
    final started = await ref
        .read(practiceLauncherProvider)
        .start(level, tokensToWin: prefs.tokensToWin, gameCode: gameCode, damaType: prefs.damaType);
    if (context.mounted) context.go(GameRoutes.match(started.gameCode, started.matchId));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error is PracticeStartException ? error.message : 'Could not start practice.')));
  }
}
