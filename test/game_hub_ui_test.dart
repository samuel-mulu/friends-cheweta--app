import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/communications/communications_repository.dart';
import 'package:friends_game_app/features/game_hub/presentation/controllers/game_hub_controller.dart';
import 'package:friends_game_app/features/game_hub/presentation/screens/game_lobby_screen.dart';
import 'package:friends_game_app/features/game_hub/presentation/widgets/game_grid.dart';
import 'package:friends_game_app/features/home/presentation/screens/home_screen.dart';
import 'package:friends_game_app/features/shell/presentation/main_shell.dart';
import 'package:friends_game_app/features/wallet/domain/wallet.dart';
import 'package:friends_game_app/features/wallet/presentation/controllers/wallet_controller.dart';

import 'support/fake_socket.dart';
import 'support/fake_communications.dart';

const _mode = GameMode(
  id: 'ludo-10',
  gameId: 'ludo',
  code: 'LUDO_10',
  name: 'Ludo 10',
  playerCount: 2,
  stakeAmountMinor: 1000,
  platformFeeBps: 500,
  turnDurationSeconds: 30,
  rulesVersion: 'LUDO_CLASSIC_V3',
  enabled: true,
);
const _catalog = GameHubState(modesByGame: {
  'LUDO': [_mode]
});

class _Hub extends GameHubController {
  _Hub(this.initial);
  final GameHubState initial;
  int reloads = 0;

  @override
  GameHubState build() => initial;

  @override
  Future<void> load() async {
    reloads++;
    state = _catalog;
  }
}

class _Wallet extends WalletController {
  @override
  WalletViewState build() => WalletViewState(
          wallet: Wallet(
        availableBalance: BigInt.from(24550),
        lockedBalance: BigInt.zero,
        currency: 'ETB',
      ));
}

const _lobbyReply = {
  'ok': true,
  'data': {
    'gameModeId': 'ludo-10',
    'myState': 'ONLINE',
    'players': [
      {
        'userId': 'opponent',
        'displayName': 'Dawit Gebremariam',
        'gameModeId': 'ludo-10',
        'state': 'READY'
      },
    ],
  },
};

Future<void> _showHub(
  WidgetTester tester, {
  required _Hub hub,
  required FakeSocket socket,
  bool lobby = false,
  double textScale = 1,
}) async {
  final router = GoRouter(initialLocation: lobby ? '/ludo' : '/home', routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, __, shell) => MainShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen())
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/wallet', builder: (_, __) => const SizedBox())
        ]),
      ],
    ),
    GoRoute(
        path: '/ludo',
        builder: (_, __) => const GameLobbyScreen(gameCode: 'LUDO')),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(SignedInAs.new),
      communicationsRepositoryProvider.overrideWithValue(EmptyCommunications()),
      gameHubControllerProvider.overrideWith(() => hub),
      gameSocketServiceProvider.overrideWithValue(socket),
      walletControllerProvider.overrideWith(_Wallet.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final (state, message) in [
    (
      const GameHubState(error: 'Game data could not load.'),
      'Game data could not load.'
    ),
    (const GameHubState(), 'No stakes are available for Ludo right now.'),
  ]) {
    testWidgets('shows Retry after $message and opens the lobby once',
        (tester) async {
      final hub = _Hub(state);
      final socket = FakeSocket()
        ..reply = (event, _) =>
            event == 'lobby:join_game' ? _lobbyReply : {'ok': true};
      await _showHub(tester, hub: hub, socket: socket, lobby: true);

      expect(find.text(message), findsOneWidget);
      expect(find.text('Practice with a bot'), findsOneWidget);
      expect(socket.sent, isNot(contains('lobby:join_game')));

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(hub.reloads, 1);
      expect(socket.sent.where((event) => event == 'lobby:join_game'),
          hasLength(1));
      expect(find.text('Ready to play'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  }

  testWidgets('an initial lobby connection failure stays visible until retry',
      (tester) async {
    final hub = _Hub(_catalog);
    var attempts = 0;
    final socket = FakeSocket()
      ..reply = (event, _) {
        if (event != 'lobby:join_game') return {'ok': true};
        if (++attempts == 1) {
          return {
            'ok': false,
            'message': 'The lobby is temporarily unavailable.'
          };
        }
        return _lobbyReply;
      };
    await _showHub(tester, hub: hub, socket: socket, lobby: true);
    expect(find.text('The lobby is temporarily unavailable.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Ready to play'), findsOneWidget);
  });

  testWidgets(
      'narrow hub and lobby fit larger text and keep custom stake in the picker',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = FakeSocket()
      ..reply =
          (event, _) => event == 'lobby:join_game' ? _lobbyReply : {'ok': true};
    await _showHub(tester, hub: _Hub(_catalog), socket: socket, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('Friends'), findsOneWidget);
    final cards = find.byType(LiveGameCard);
    expect(tester.getSize(cards.at(2)).width,
        greaterThan(tester.getSize(cards.first).width * 2));

    await tester.tap(find.text('Ludo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Players'), findsOneWidget);
    expect(find.text('Custom stake'), findsNothing);
    await tester.tap(find.text('Your stake'));
    await tester.pumpAndSettle();
    expect(find.text('Custom stake'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
