import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/widgets/app_logo.dart';
import 'package:friends_game_app/features/chat/presentation/widgets/messages_button.dart';
import 'package:friends_game_app/features/shell/presentation/widgets/app_sidebar.dart';
import 'package:friends_game_app/features/wallet/presentation/widgets/balance_pill.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  static const _sidebarBreakpoint = 840.0;

  void _goToBranch(int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _sidebarBreakpoint) {
          return Scaffold(
            body: Row(children: [
              AppSidebar(selectedIndex: index, onDestinationSelected: _goToBranch),
              Expanded(child: navigationShell),
            ]),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: index == 0
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    AppLogoMark(size: 30),
                    SizedBox(width: 10),
                    Flexible(child: Text('Friends', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ])
                : Text(_titleForIndex(index)),
            actions: [
              // The wallet tab shows the balance itself.
              if (index != 1) const BalancePill(),
              const MessagesButton(),
              const SizedBox(width: 4),
            ],
          ),
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
        );
      },
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
