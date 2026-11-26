import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/app/router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/theme/app_theme.dart';
import 'package:friends_game_app/core/theme/theme_controller.dart';
import 'package:friends_game_app/features/auth/domain/auth_state.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/communications/communications_host.dart';
import 'package:friends_game_app/features/payments/data/payment_repository.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

class FriendsGameApp extends ConsumerWidget {
  const FriendsGameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated && previous?.status != AuthStatus.authenticated) {
        unawaited(ref.read(gameSocketStatusProvider.notifier).connect().catchError((_) {}));
      }
      if (next.status == AuthStatus.unauthenticated && previous?.status == AuthStatus.authenticated) {
        unawaited(ref.read(gameSocketStatusProvider.notifier).disconnect());
      }
    });

    ref.listen(gameSocketStatusProvider, (previous, next) {
      if (next == GameSocketStatus.connected && previous != next) _refreshPayments(ref);
    });
    ref.listen(_walletEventsProvider, (_, next) {
      if (next.hasValue) _refreshPayments(ref);
    });

    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Friends Game Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => CommunicationsHost(child: child ?? const SizedBox.shrink()),
    );
  }

  void _refreshPayments(WidgetRef ref) {
    if (ref.read(authControllerProvider).status != AuthStatus.authenticated) return;
    ref.invalidate(depositConfigProvider);
    ref.invalidate(activeDepositAttemptsProvider);
    ref.invalidate(depositHistoryProvider);
    ref.invalidate(withdrawalHistoryProvider);
    unawaited(ref.read(walletControllerProvider.notifier).refresh());
  }
}

final _walletEventsProvider = StreamProvider.autoDispose((ref) =>
  ref.watch(gameSocketServiceProvider).events.where((event) => event.name == 'wallet:updated'));
