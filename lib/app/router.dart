import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/features/auth/domain/auth_state.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/auth/presentation/screens/login_screen.dart';
import 'package:friends_game_app/features/auth/presentation/screens/register_screen.dart';
import 'package:friends_game_app/features/auth/presentation/screens/splash_screen.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/game_hub/presentation/screens/game_hub_screen.dart';
import 'package:friends_game_app/features/dama/presentation/screens/dama_match_screen.dart';
import 'package:friends_game_app/features/game_hub/domain/game_routes.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/game_hub/presentation/screens/game_lobby_screen.dart';
import 'package:friends_game_app/features/history/presentation/screens/history_screen.dart';
import 'package:friends_game_app/features/history/presentation/screens/match_detail_screen.dart';
import 'package:friends_game_app/features/history/presentation/screens/match_replay_screen.dart';
import 'package:friends_game_app/features/home/presentation/screens/home_screen.dart';
import 'package:friends_game_app/features/chat/presentation/screens/chats_screen.dart';
import 'package:friends_game_app/features/chat/presentation/screens/direct_chat_screen.dart';
import 'package:friends_game_app/features/ludo/presentation/screens/ludo_match_screen.dart';
import 'package:friends_game_app/features/match/presentation/screens/match_result_screen.dart';
import 'package:friends_game_app/features/live_lobby/presentation/screens/live_lobby_screen.dart';
import 'package:friends_game_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:friends_game_app/features/payments/presentation/screens/deposit_screen.dart';
import 'package:friends_game_app/features/payments/presentation/screens/withdrawal_screen.dart';
import 'package:friends_game_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:friends_game_app/features/shell/presentation/main_shell.dart';
import 'package:friends_game_app/features/wallet/presentation/screens/wallet_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (auth.status == AuthStatus.initializing) return location == '/splash' ? null : '/splash';
      final authRoute = location == '/login' || location == '/register';
      if (auth.status == AuthStatus.unauthenticated) return authRoute ? null : '/login';
      if (auth.status == AuthStatus.authenticated && (authRoute || location == '/splash')) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => MainShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (_, __) => const HistoryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      GoRoute(path: '/deposit', builder: (_, __) => const DepositScreen()),
      GoRoute(path: '/withdraw', builder: (_, __) => const WithdrawalScreen()),
      GoRoute(path: '/games', builder: (_, __) => const GameHubScreen()),
      GoRoute(path: '/chats', builder: (_, __) => const ChatsScreen()),
      GoRoute(
        path: '/chats/:userId',
        builder: (_, state) => DirectChatScreen(
          peerId: state.pathParameters['userId'] ?? '',
          peerName: state.extra is String ? state.extra as String : null,
        ),
      ),
      // Each live game: its lobby (rooms + practice) and the live matchmaking room.
      for (final code in liveGameCodes) ...[
        GoRoute(path: GameRoutes.lobby(code), builder: (_, __) => GameLobbyScreen(gameCode: code)),
        GoRoute(
          path: GameRoutes.matchmaking(code),
          builder: (_, state) {
            final mode = state.extra;
            if (mode is GameMode) return LiveLobbyScreen(mode: mode);
            return Scaffold(body: Center(child: Text('Choose a ${GameRoutes.displayName(code)} room first.')));
          },
        ),
      ],
      GoRoute(path: '/ludo/match/:matchId', builder: (_, state) => LudoMatchScreen(matchId: state.pathParameters['matchId'] ?? '')),
      GoRoute(path: '/dama/match/:matchId', builder: (_, state) => DamaMatchScreen(matchId: state.pathParameters['matchId'] ?? '')),
      for (final code in liveGameCodes)
        GoRoute(
          path: '${GameRoutes.lobby(code)}/result/:matchId',
          builder: (_, state) => MatchResultScreen(gameCode: code, matchId: state.pathParameters['matchId'] ?? ''),
        ),
      GoRoute(path: '/history/:matchId', builder: (_, state) => MatchDetailScreen(matchId: state.pathParameters['matchId'] ?? '')),
      GoRoute(path: '/history/:matchId/replay', builder: (_, state) => MatchReplayScreen(matchId: state.pathParameters['matchId'] ?? '')),
    ],
  );
});
