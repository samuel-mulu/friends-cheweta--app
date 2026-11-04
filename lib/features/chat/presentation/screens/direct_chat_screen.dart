import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/chat_inbox_controller.dart';
import 'package:friends_game_app/features/chat/application/direct_chat_controller.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/chat_thread.dart';

/// A private conversation with one player.
class DirectChatScreen extends ConsumerWidget {
  const DirectChatScreen({super.key, required this.peerId, this.peerName});

  final String peerId;
  final String? peerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(directChatControllerProvider(peerId));
    final controller = ref.read(directChatControllerProvider(peerId).notifier);
    final me = ref.watch(authControllerProvider.select((auth) => auth.user?.id));
    final name = peerName ??
        ref.watch(chatInboxControllerProvider.select((s) => s.conversations.where((c) => c.peerId == peerId).firstOrNull?.peerName)) ??
        'Player';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(radius: 16, child: Text(name.isEmpty ? '?' : name[0].toUpperCase())),
          const SizedBox(width: 10),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: chat.loading && chat.messages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ChatThread(
              lines: [
                for (final m in chat.messages)
                  ChatLine(id: m.id, text: m.text, senderName: m.senderName, mine: m.senderId == me, createdAt: m.createdAt),
              ],
              sending: chat.sending,
              error: chat.error,
              showSenderNames: false,
              emptyText: 'Start a conversation with $name',
              onSend: controller.send,
              onLoadOlder: chat.hasMore ? controller.loadOlder : null,
            ),
    );
  }
}
