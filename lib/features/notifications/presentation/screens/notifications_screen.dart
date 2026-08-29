import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:friends_game_app/core/widgets/app_error_view.dart';
import 'package:friends_game_app/features/notifications/presentation/controllers/notifications_controller.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);
    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsControllerProvider.notifier).load(),
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 12, 12),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              Expanded(child: Text('Notifications', style: Theme.of(context).textTheme.headlineSmall)),
              if (state.unreadCount > 0) TextButton(onPressed: () => ref.read(notificationsControllerProvider.notifier).markAllRead(), child: const Text('Mark all read')),
            ]),
          ),
        ),
        if (state.loading && state.items.isEmpty)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
        else if (state.error != null && state.items.isEmpty)
          SliverFillRemaining(child: AppErrorView(message: state.error!, onRetry: () => ref.read(notificationsControllerProvider.notifier).load()))
        else if (state.items.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: Center(child: Text('No notifications yet.')))
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList.separated(
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = state.items[index];
                return Card(
                  child: ListTile(
                    onTap: () => ref.read(notificationsControllerProvider.notifier).markRead(item.id),
                    leading: CircleAvatar(child: Icon(_icon(item.type))),
                    title: Row(children: [Expanded(child: Text(item.title)), if (!item.isRead) const Icon(Icons.circle, size: 8)]),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${item.message}\n${DateFormat('MMM d · h:mm a').format(item.createdAt.toLocal())}'),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),
      ]),
    );
  }

  IconData _icon(String type) {
    final value = type.toUpperCase();
    if (value.contains('DEPOSIT')) return Icons.south_west_rounded;
    if (value.contains('WITHDRAW')) return Icons.north_east_rounded;
    if (value.contains('MATCH') || value.contains('GAME')) return Icons.sports_esports_rounded;
    return Icons.notifications_none_rounded;
  }
}
