import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/features/chat/application/chat_inbox_controller.dart';

/// Opens the private-message inbox; shows the unread total.
class MessagesButton extends ConsumerWidget {
  const MessagesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(chatInboxControllerProvider.select((s) => s.unreadTotal));
    return IconButton(
      tooltip: 'Messages',
      onPressed: () => context.push('/chats'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.forum_outlined),
      ),
    );
  }
}
