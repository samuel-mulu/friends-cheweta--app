import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/theme/app_colors.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/messages_button.dart';
import 'package:friends_game_app/features/shell/presentation/widgets/app_sidebar.dart';
import 'package:friends_game_app/features/wallet/presentation/widgets/balance_pill.dart';

/// The frame around every main page: a top bar with the balance always in
/// reach, and the sidebar hidden at the side (on every screen size) until the
/// menu button or an edge swipe opens it.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _drawerOpen = false;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  void _goToBranch(int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    // Phone back: an open sidebar closes first; Wallet, History, Alerts and
    // Profile go back to Home; only Home leaves the app.
    return PopScope(
      canPop: index == 0 || _drawerOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goToBranch(0);
      },
      child: Scaffold(
        onDrawerChanged: (open) => setState(() => _drawerOpen = open),
        appBar: _TopBar(index: index, menu: true),
        drawer: Drawer(
          width: AppSidebar.width,
          child: AppSidebar(
            selectedIndex: index,
            onDestinationSelected: (next) {
              _goToBranch(next);
              Navigator.of(context).pop();
            },
          ),
        ),
        body: navigationShell,
      ),
    );
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({required this.index, required this.menu});
  final int index;

  /// Show the menu button (phones: the sidebar is a drawer).
  final bool menu;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 60,
      automaticallyImplyLeading: false,
      titleSpacing: menu ? 0 : 16,
      shape: Border(bottom: BorderSide(color: AppPalette.of(context).surfaceAlt)),
      leading: menu
          ? Builder(
              builder: (context) => IconButton(
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            )
          : null,
      title: index == 0
          ? Semantics(
              header: true,
              label: 'Friends Chewata',
              child: const ExcludeSemantics(child: AppWordmark(size: 40)),
            )
          : Text(_titleForIndex(index)),
      actions: [
        // The wallet page shows the balance itself.
        if (index != 1) const BalancePill(),
        const MessagesButton(),
        const SizedBox(width: 4),
      ],
    );
  }

  String _titleForIndex(int index) => switch (index) {
        1 => 'Wallet',
        2 => 'History',
        3 => 'Alerts',
        4 => 'Profile',
        _ => 'Friends',
      };
}
