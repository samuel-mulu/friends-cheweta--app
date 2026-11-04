import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';

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
}

/// Last level chosen this session (for "Play again" on the result screen).
final lastPracticeLevelProvider = StateProvider<PracticeLevel?>((ref) => null);

class PracticeLauncher {
  PracticeLauncher(this._ref);
  final Ref _ref;
  static const _uuid = Uuid();

  /// Starts (or resumes) a practice game; returns the match id.
  Future<String> start(PracticeLevel level) async {
    final ack = await _ref.read(gameSocketServiceProvider).emitWithAck('practice:start', {
      'commandId': _uuid.v4(),
      'level': level.code,
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
    return matchId;
  }
}

class PracticeStartException implements Exception {
  const PracticeStartException(this.message);
  final String message;
  @override
  String toString() => message;
}

final practiceLauncherProvider = Provider<PracticeLauncher>(PracticeLauncher.new);

/// Level picker → start → open the match. Shared by the Ludo hub and the result screen.
Future<void> showPracticeSheet(BuildContext context, WidgetRef ref) async {
  final level = await showModalBottomSheet<PracticeLevel>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
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
          for (final level in PracticeLevel.values)
            ListTile(
              leading: Icon(level.icon),
              title: Text(level.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(level.description),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, level),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (level == null || !context.mounted) return;
  await startPractice(context, ref, level);
}

Future<void> startPractice(BuildContext context, WidgetRef ref, PracticeLevel level) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final matchId = await ref.read(practiceLauncherProvider).start(level);
    if (context.mounted) context.go('/ludo/match/$matchId');
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error is PracticeStartException ? error.message : 'Could not start practice.')));
  }
}
