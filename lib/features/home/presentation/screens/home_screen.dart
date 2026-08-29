import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_spacing.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final socketStatus = ref.watch(gameSocketStatusProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screen),
      children: [
        Text('Welcome back', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(user?.fullName ?? 'Player', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Pick a game and find a match. Balance and payments are in the sidebar.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(child: Text('Games', style: Theme.of(context).textTheme.titleLarge)),
            TextButton(onPressed: () => context.push('/games'), child: const Text('View all')),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/ludo'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.grid_view_rounded),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ludo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
                        SizedBox(height: 4),
                        Text('Real-time 1v1 • Choose your stake'),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(
              socketStatus == GameSocketStatus.connected ? Icons.circle : Icons.circle_outlined,
              size: 10,
              color: socketStatus == GameSocketStatus.connected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              socketStatus == GameSocketStatus.connected ? 'Realtime ready' : 'Realtime reconnects when needed',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}
