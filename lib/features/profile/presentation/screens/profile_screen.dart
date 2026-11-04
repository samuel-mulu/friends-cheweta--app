import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/theme/theme_controller.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final theme = ref.watch(themeModeProvider);
    final prefs = ref.watch(playerPreferencesProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(auth.user?.fullName ?? 'Player'),
            subtitle: Text(auth.user?.phoneNumber ?? ''),
            trailing: Text(auth.user?.status ?? ''),
          ),
        ),
        const SizedBox(height: 24),
        Text('Preferences', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.brightness_6_outlined),
              title: const Text('Appearance'),
              trailing: DropdownButton<ThemeMode>(
                value: theme,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (mode) {
                  if (mode != null) ref.read(themeModeProvider.notifier).setMode(mode);
                },
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.volume_up_outlined),
              title: const Text('Game sounds'),
              subtitle: const Text('Presentation sounds only. Game state remains server-authoritative.'),
              value: prefs.soundEnabled,
              onChanged: (value) => ref.read(playerPreferencesProvider.notifier).setSound(value),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.vibration_rounded),
              title: const Text('Haptics'),
              value: prefs.hapticsEnabled,
              onChanged: (value) => ref.read(playerPreferencesProvider.notifier).setHaptics(value),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.speed_rounded),
              title: const Text('Fast animations'),
              subtitle: const Text('Quicker dice and token moves for experienced players.'),
              value: prefs.fastAnimations,
              onChanged: (value) => ref.read(playerPreferencesProvider.notifier).setFastAnimations(value),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
