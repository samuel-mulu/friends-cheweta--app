import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/chat_thread.dart';

/// Match chat in a bottom sheet.
class MatchChatSheet extends ConsumerWidget {
  const MatchChatSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(matchChatControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(children: [
                Expanded(child: Text('Match chat', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
            ),
            Expanded(
              child: chat.loading && chat.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ChatThread(
                      lines: [
                        for (final m in chat.messages)
                          ChatLine(
                            id: m.id,
                            text: m.text,
                            senderName: m.sender.displayName,
                            mine: m.sender.userId == me,
                            createdAt: m.createdAt,
                          ),
                      ],
                      sending: chat.sending,
                      error: chat.error,
                      emptyText: 'Say good luck 👋',
                      onSend: ref.read(matchChatControllerProvider.notifier).send,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
