import 'package:friends_game_app/core/utils/phone_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/theme/app_motion.dart';
import 'package:friends_game_app/core/theme/app_type.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/messages_button.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// The sidebar (a drawer on phones, fixed at the side on wide screens):
/// who I am, my money, and where to go.
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, required this.selectedIndex, required this.onDestinationSelected});

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const width = 304.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final user = ref.watch(authControllerProvider).user;
    final wallet = ref.watch(walletControllerProvider).wallet;
    final unread = ref.watch(notificationsControllerProvider.select((state) => state.unreadCount));
    final messages = ref.watch(messagesUnreadCountProvider);

    String? badge(int count) => count > 0 ? (count > 99 ? '99+' : '$count') : null;

    return SizedBox(
      width: width,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Row(children: [
              PlayerAvatar(name: user?.fullName ?? 'Player', size: 48, ring: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.fullName ?? 'Player', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                  if (user != null) Text(formatPhone(user.phoneNumber), style: theme.textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
          Divider(color: palette.surfaceAlt),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _BalanceCard(
              available: wallet?.availableBalance,
              locked: wallet?.lockedBalance,
              onDeposit: () => context.push('/deposit'),
              onWithdraw: () => context.push('/withdraw'),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              _NavTile(icon: Icons.sports_esports_outlined, selectedIcon: Icons.sports_esports_rounded, label: 'Games', selected: selectedIndex == 0, onTap: () => onDestinationSelected(0)),
              _NavTile(icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet_rounded, label: 'Wallet', selected: selectedIndex == 1, onTap: () => onDestinationSelected(1)),
              _NavTile(icon: Icons.history_rounded, selectedIcon: Icons.history_rounded, label: 'Match history', selected: selectedIndex == 2, onTap: () => onDestinationSelected(2)),
              _NavTile(
                icon: Icons.notifications_none_rounded,
                selectedIcon: Icons.notifications_rounded,
                label: 'Alerts',
                selected: selectedIndex == 3,
                badge: badge(unread),
                onTap: () => onDestinationSelected(3),
              ),
              _NavTile(
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                label: 'Messages',
                selected: false,
                badge: badge(messages),
                onTap: () {
                  final router = GoRouter.of(context);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen == true) Navigator.of(context).pop();
                  router.push('/messages');
                },
              ),
              _NavTile(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Profile and settings', selected: selectedIndex == 4, onTap: () => onDestinationSelected(4)),
            ]),
          ),
          Divider(color: palette.surfaceAlt),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Align(alignment: Alignment.centerLeft, child: ExcludeSemantics(child: AppWordmark(size: 32))),
          ),
        ]),
      ),
    );
  }
}

/// The balance in gold on the night inset, with the two money actions.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.available, required this.locked, required this.onDeposit, required this.onWithdraw});

  final BigInt? available;
  final BigInt? locked;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppPalette.of(context);
    final lockedNow = locked != null && locked! > BigInt.zero;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Balance', style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        available == null
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Skeleton(height: 28, width: 150))
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(MoneyFormatter.minorToEtb(available!), style: AppType.money(size: 32, color: palette.money)),
              ),
        if (lockedNow) ...[
          const SizedBox(height: 2),
          Text('${MoneyFormatter.minorToEtb(locked!)} in a match', style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: onDeposit,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Deposit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: onWithdraw,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Withdraw', maxLines: 1, softWrap: false),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.selectedIcon, required this.label, required this.selected, required this.onTap, this.badge});

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: selected,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.state,
              curve: AppMotion.curve,
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: selected ? palette.surfaceAlt : Colors.transparent),
              child: Row(children: [
                Icon(selected ? selectedIcon : icon, size: 22, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppType.ui(
                      size: 15.5,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(999)),
                    child: Text(badge!, style: AppType.ui(size: 12, weight: FontWeight.w700, color: AppColors.onGold)),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 251962520885 -> +251 96 252 0885 (other formats unchanged).
