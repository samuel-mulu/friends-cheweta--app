import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/utils/money_formatter.dart';
import 'package:friends_game_app/core/widgets/ui.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/messages_button.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

/// The drawer (phones) or side rail (tablets): who I am, my money, where to go.
class AppSidebar extends ConsumerWidget {
  const AppSidebar({super.key, required this.selectedIndex, required this.onDestinationSelected});

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const width = 300.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).user;
    final wallet = ref.watch(walletControllerProvider).wallet;
    final unread = ref.watch(notificationsControllerProvider.select((state) => state.unreadCount));
    final messages = ref.watch(messagesUnreadCountProvider);

    return SizedBox(
      width: width,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              PlayerAvatar(name: user?.fullName ?? 'Player', size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.fullName ?? 'Player', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                  if (user != null) Text(_phone(user.phoneNumber), style: theme.textTheme.bodySmall),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _BalanceCard(
              available: wallet?.availableBalance,
              locked: wallet?.lockedBalance,
              onDeposit: () => context.push('/deposit'),
              onWithdraw: () => context.push('/withdraw'),
            ),
          ),
          const SizedBox(height: 16),
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
                badge: unread > 0 ? (unread > 99 ? '99+' : '$unread') : null,
                onTap: () => onDestinationSelected(3),
              ),
              _NavTile(
                icon: Icons.markunread_outlined, selectedIcon: Icons.markunread_rounded, label: 'Messages', selected: false,
                badge: messages > 0 ? (messages > 99 ? '99+' : '$messages') : null,
                onTap: () {
                  final router = GoRouter.of(context);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen == true) Navigator.of(context).pop();
                  router.push('/messages');
                },
              ),
              _NavTile(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Profile & settings', selected: selectedIndex == 4, onTap: () => onDestinationSelected(4)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Navy brand card: the balance in gold, with the two money actions.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.available, required this.locked, required this.onDeposit, required this.onWithdraw});

  final BigInt? available;
  final BigInt? locked;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final lockedNow = locked != null && locked! > BigInt.zero;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Balance', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        available == null
            ? const Skeleton(height: 30, width: 140)
            : Text(
                MoneyFormatter.minorToEtb(available!),
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
        if (lockedNow) ...[
          const SizedBox(height: 2),
          Text(
            '${MoneyFormatter.minorToEtb(locked!)} in a match',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: onDeposit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.navy,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Deposit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: onWithdraw,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              Icon(selected ? selectedIcon : icon, size: 22, color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                  child: Text(badge!, style: TextStyle(color: scheme.onPrimary, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 251962520885 -> +251 96 252 0885 (other formats unchanged).
String _phone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 12 && digits.startsWith('251')) {
    return '+251 ${digits.substring(3, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
  }
  return raw;
}
