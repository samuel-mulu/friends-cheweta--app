import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/match/application/match_reactions_controller.dart';
import 'package:friends_game_app/features/match/presentation/widgets/match_chat_sheet.dart';

/// Quick reactions picker; sends the chosen one to the match.
Future<void> showMatchReactionPicker(BuildContext context, WidgetRef ref) async {
  final reaction = await showModalBottomSheet<MatchReaction>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final r in MatchReaction.values)
              ActionChip(
                label: Text(r.display, style: TextStyle(fontSize: r.isEmoji ? 22 : 14, fontWeight: FontWeight.w700)),
                onPressed: () => Navigator.pop(context, r),
              ),
          ],
        ),
      ),
    ),
  );
  if (reaction != null) await ref.read(matchReactionsProvider.notifier).send(reaction);
}

/// Match chat; unread counting pauses while it is open.
Future<void> openMatchChat(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(matchChatControllerProvider.notifier);
  controller.setPanelOpen(true);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const MatchChatSheet(),
  );
  controller.setPanelOpen(false);
}

/// "Leave the match?" — leaving a running match forfeits it.
Future<bool> confirmLeaveMatch(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the match?'),
        content: const Text('Leaving now forfeits this match and your stake.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep playing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    ) ==
    true;
