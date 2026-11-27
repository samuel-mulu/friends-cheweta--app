import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/variant_picker.dart';
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

/// Practice games started (or resumed) on this device, so the match screens
/// can say that leaving one costs nothing.
final practiceMatchIdsProvider = StateProvider<Set<String>>((ref) => const {});

class PracticeLauncher {
  PracticeLauncher(this._ref);
  final Ref _ref;
  static const _uuid = Uuid();

  /// Starts (or resumes) a practice game. A resumed game may be another game
  /// than [gameCode]; the result says which screen to open.
  /// [variant] picks the game type (e.g. Dama እግረኛ, Ludo መመለስ የሌለበት).
  Future<PracticeStart> start(
    PracticeLevel level, {
    int tokensToWin = 4,
    String gameCode = GameCodes.ludo,
    GameVariant? variant,
  }) async {
    final ack = await _ref.read(gameSocketServiceProvider).emitWithAck('practice:start', {
      'commandId': _uuid.v4(),
      'level': level.code,
      if (gameCode == GameCodes.ludo) 'tokensToWin': tokensToWin,
      if (gameCode != GameCodes.ludo) 'game': gameCode,
      if (variant != null && variant.gameCode == gameCode) 'rulesVersion': variant.rulesVersion,
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
    _ref.read(practiceMatchIdsProvider.notifier).update((ids) => {...ids, matchId});
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

/// Type (and Ludo goal), then the level → start → open the match. The same
/// pickers as the lobby's ready panel, so practice plays exactly what money
/// games do. Shared by the game lobbies and result screens.
Future<void> showPracticeSheet(BuildContext context, WidgetRef ref, {String gameCode = GameCodes.ludo}) async {
  final prefs = ref.read(playerPreferencesProvider);
  final variants = GameVariants.of(gameCode);
  var variant = prefs.variantFor(gameCode);
  var goal = prefs.tokensToWin;
  final level = await showModalBottomSheet<PracticeLevel>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: SheetHeader(title: 'Practice vs computer', subtitle: 'Free. Does not count for stats or the leaderboard.'),
              ),
              if (variants.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: VariantPicker(variants: variants, selected: variant, onChanged: (next) => setSheet(() => variant = next)),
                ),
              if (gameCode == GameCodes.ludo)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: GoalChips(selected: goal, onChanged: (next) => setSheet(() => goal = next)),
                ),
              for (final level in PracticeLevel.values)
                ListTile(
                  leading: Icon(level.icon),
                  title: Text(level.label),
                  subtitle: Text(level.describe(gameCode)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, level),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
  if (level == null || !context.mounted) return;
  final preferences = ref.read(playerPreferencesProvider.notifier);
  if (variant != null) await preferences.setVariant(variant!);
  if (gameCode == GameCodes.ludo) await preferences.setTokensToWin(goal);
  if (!context.mounted) return;
  await startPractice(context, ref, level, gameCode: gameCode);
}

Future<void> startPractice(BuildContext context, WidgetRef ref, PracticeLevel level, {String gameCode = GameCodes.ludo}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    // "Play again" reuses the last goal (Ludo) and type chosen.
    final prefs = ref.read(playerPreferencesProvider);
    final started = await ref
        .read(practiceLauncherProvider)
        .start(level, tokensToWin: prefs.tokensToWin, gameCode: gameCode, variant: prefs.variantFor(gameCode));
    if (context.mounted) context.go(GameRoutes.match(started.gameCode, started.matchId));
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error is PracticeStartException ? error.message : 'Could not start practice.')));
  }
}
