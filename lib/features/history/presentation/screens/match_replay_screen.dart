import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/history/presentation/controllers/match_history_controller.dart';

class MatchReplayScreen extends ConsumerWidget {
  const MatchReplayScreen({super.key, required this.matchId});
  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replay = ref.watch(matchReplayProvider(matchId));
    return Scaffold(
      appBar: AppBar(title: const Text('Match timeline')),
      body: replay.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppErrorView(message: 'Could not load the match timeline.', onRetry: () => ref.invalidate(matchReplayProvider(matchId))),
        data: (value) => value.events.isEmpty
            ? const Center(child: Text('No replay events were recorded for this match.'))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: value.events.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final event = value.events[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text('${index + 1}')),
                      title: Text(_label(event.type)),
                      subtitle: Text('v${event.version} · ${DateFormat('h:mm:ss a').format(event.createdAt.toLocal())}'),
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _label(String value) => value.toLowerCase().replaceAll('_', ' ').split(' ').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}
