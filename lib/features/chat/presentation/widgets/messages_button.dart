import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/features/communications/communications_controllers.dart';
import 'package:friends_game_app/features/chat/application/chat_inbox_controller.dart';

final messagesUnreadCountProvider = Provider<int>((ref) =>
    ref.watch(communicationsUnreadProvider) +
    ref.watch(
        chatInboxControllerProvider.select((state) => state.unreadTotal)));

/// Opens announcements and feedback, with a shortcut to player chat.
class MessagesButton extends ConsumerWidget {
  const MessagesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(messagesUnreadCountProvider);
    return IconButton(
      tooltip: 'Messages',
      onPressed: () => context.push('/messages'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: const Icon(Icons.markunread_outlined),
      ),
    );
  }
}
