import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/chat_inbox_controller.dart';
import 'package:friends_game_app/features/chat/domain/direct_message.dart';

/// Private conversations, newest first, with unread counts.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(chatInboxControllerProvider);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(chatInboxControllerProvider.notifier).refresh(),
        child: inbox.conversations.isEmpty
            ? ListView(children: [
                const SizedBox(height: 120),
                Icon(Icons.forum_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    inbox.loading ? 'Loading…' : (inbox.error ?? 'No messages yet.\nTap the chat icon next to a player in the lobby.'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ])
            : ListView.separated(
                itemCount: inbox.conversations.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (context, index) => _ConversationTile(conversation: inbox.conversations[index], me: me),
              ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.me});
  final Conversation conversation;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0;
    final prefix = c.lastMessage.senderId == me ? 'You: ' : '';
    final local = c.lastMessage.createdAt.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final when = sameDay
        ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
        : '${local.day}/${local.month}';
    return ListTile(
      leading: CircleAvatar(child: Text(c.peerName.isEmpty ? '?' : c.peerName[0].toUpperCase())),
      title: Text(c.peerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
      subtitle: Text('$prefix${c.lastMessage.text}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(when, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          if (unread) Badge(label: Text('${c.unread}')),
        ],
      ),
      onTap: () => context.push('/chats/${c.peerId}', extra: c.peerName),
    );
  }
}
