import 'package:friends_game_app/core/utils/phone_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/theme_controller.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/profile/presentation/controllers/preferences_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final mode = ref.watch(themeModeProvider);
    final prefs = ref.watch(playerPreferencesProvider);
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    Widget divider() => Divider(indent: 56, color: palette.surfaceAlt);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            AppPanel(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                PlayerAvatar(name: auth.user?.fullName ?? 'Player', size: 56, ring: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(auth.user?.fullName ?? 'Player', style: theme.textTheme.titleLarge),
                    if (auth.user != null) Text(formatPhone(auth.user!.phoneNumber), style: theme.textTheme.bodySmall),
                  ]),
                ),
                if ((auth.user?.status ?? '').isNotEmpty)
                  StatusPill(
                    label: auth.user!.status[0] + auth.user!.status.substring(1).toLowerCase(),
                    tone: auth.user!.status == 'ACTIVE' ? StatusTone.live : StatusTone.muted,
                  ),
              ]),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Appearance'),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.phone_android_rounded)),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => ref.read(themeModeProvider.notifier).setMode(selection.first),
            ),
            const SizedBox(height: 24),
            const SectionHeader(title: 'Play'),
            AppPanel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: const Text('Game sounds'),
                  subtitle: const Text('Dice, moves and wins.'),
                  value: prefs.soundEnabled,
                  onChanged: (value) => ref.read(playerPreferencesProvider.notifier).setSound(value),
                ),
                divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.vibration_rounded),
                  title: const Text('Haptics'),
                  value: prefs.hapticsEnabled,
                  onChanged: (value) => ref.read(playerPreferencesProvider.notifier).setHaptics(value),
                ),
                divider(),
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
            const SectionHeader(title: 'Account'),
            AppPanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Change password'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/change-password'),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ref.read(authControllerProvider.notifier).logout(),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.6), width: 1.5),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
