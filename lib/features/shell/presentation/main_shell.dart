import 'package:flutter/material.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/messages_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/features/shell/presentation/widgets/app_sidebar.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _sidebarBreakpoint = 840.0;

  void _goToBranch(int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSidebar = constraints.maxWidth >= _sidebarBreakpoint;

        if (useSidebar) {
          return Scaffold(
            body: Row(
              children: [
                AppSidebar(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: _goToBranch,
                ),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_titleForIndex(navigationShell.currentIndex)),
            centerTitle: false,
            actions: const [MessagesButton(), SizedBox(width: 4)],
          ),
          drawer: Drawer(
            width: AppSidebar.width,
            child: AppSidebar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) {
                _goToBranch(index);
                Navigator.of(context).pop();
              },
            ),
          ),
          body: navigationShell,
        );
      },
    );
  }

  String _titleForIndex(int index) => switch (index) {
        0 => 'Home',
        1 => 'Wallet',
        2 => 'History',
        3 => 'Alerts',
        4 => 'Profile',
        _ => 'Friends Game Hub',
      };
}
