import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/theme/app_theme.dart';
import 'package:friends_game_app/features/game_hub/domain/game_mode.dart';
import 'package:friends_game_app/features/karta/domain/karta_table.dart';
import 'package:friends_game_app/features/karta/presentation/screens/karta_table_screen.dart';
import 'package:friends_game_app/features/live_lobby/domain/lobby_player.dart';
import 'package:friends_game_app/features/live_lobby/presentation/controllers/live_lobby_controller.dart';

GameMode _mode(String id, int amount, {int players = 2, String rules = 'LUDO_CLASSIC_V3'}) => GameMode(
      id: id,
      gameId: 'g',
      code: id.toUpperCase(),
      name: id,
      playerCount: players,
      stakeAmountMinor: amount,
      platformFeeBps: 1000,
      turnDurationSeconds: 30,
      rulesVersion: rules,
      enabled: true,
    );

LobbyPlayer _ready(String id, String stake, {int goal = 4}) => LobbyPlayer.fromJson({
      'userId': id,
      'displayName': id,
      'state': 'READY',
      'gameModeId': stake,
      'tokensToWin': goal,
    });

final _table = KartaTable.fromJson({
  'id': 't1',
  'gameModeId': 'karta-table',
  'stakeMinor': '5000',
  'maxSeats': 4,
  'freeSeats': 0,
  'status': 'PLAYING',
  'starterId': 'a',
  'receiverId': 'b',
  'queue': ['me', 'd'],
  'round': 3,
  'matchId': 'm3',
  'players': [
    {'userId': 'a', 'fullName': 'Abebe Kebede'},
    {'userId': 'b', 'fullName': 'Bethlehem Alemu'},
    {'userId': 'me', 'fullName': 'Me Myself'},
    {'userId': 'd', 'fullName': 'Dawit Gebremariam'},
  ],
  'raise': {'amountMinor': '10000', 'byUserId': 'a'},
});

void main() {
  group('3–4 player stakes', () {
    final stakes = [_mode('l2-10', 1000), _mode('l2-50', 5000), _mode('l4-10', 1000, players: 4), _mode('l4-50', 5000, players: 4)];

    test('the lobby offers the table sizes and lists stakes of one size', () {
      final state = LiveLobbyState(gameCode: 'LUDO', stakes: stakes, myStakeId: 'l2-50');
      expect(state.offeredPlayerCounts, [2, 4]);
      expect(state.stakesOf(players: 4).map((s) => s.id), ['l4-10', 'l4-50']);
      // Switching size keeps the amount when that size has it.
      expect(state.stakeFor(rules: state.myRules, players: 4, amountMinor: 5000)?.id, 'l4-50');
      expect(state.stakeFor(rules: state.myRules, players: 4, amountMinor: 2000)?.id, 'l4-10');
    });

    test('a table fills from players ready at my stake and goal, me included', () {
      final state = LiveLobbyState(
        gameCode: 'LUDO',
        stakes: stakes,
        myStakeId: 'l4-10',
        currentUserId: 'me',
        myState: LobbyPlayerState.ready,
        players: [_ready('me', 'l4-10'), _ready('x', 'l4-10'), _ready('y', 'l4-10', goal: 2), _ready('z', 'l2-10')],
      );
      expect(state.tableFill(tokensToWin: 4), 2);
      expect(state.readyCountOfPlayers(4), 2);
      expect(state.readyCountOfPlayers(2), 1);
    });

    test('everyone in one match pays in: 4 players = 4 stakes; a Karta table round = 2', () {
      final ludo4 = _mode('l4', 1000, players: 4);
      expect(ludo4.isAutoTable, isTrue);
      expect(ludo4.estimatedWinnerPayoutMinor, 3600);
      final kartaTable = _mode('kt', 1000, players: 4, rules: kartaTableRules);
      expect(kartaTable.isKartaTable, isTrue);
      expect(kartaTable.isAutoTable, isFalse);
      expect(kartaTable.isMultiplayer, isTrue);
      expect(kartaTable.estimatedWinnerPayoutMinor, 1800);
      expect(_mode('l2', 1000).isMultiplayer, isFalse);
    });
  });

  group('Karta table', () {
    test('knows who deals, who receives and who waits where', () {
      expect(_table.roleOf('a'), KartaSeatRole.starter);
      expect(_table.roleOf('b'), KartaSeatRole.receiver);
      expect(_table.roleOf('me'), KartaSeatRole.waiting);
      expect(_table.queuePlace('me'), 1);
      expect(_table.queuePlace('d'), 2);
      expect(_table.inRound('b'), isTrue);
      expect(_table.inRound('me'), isFalse);
      expect(_table.stakeMinor, 5000);
      expect(_table.raise?.amountMinor, 10000);
    });

    Future<void> showStrip(WidgetTester tester, String me) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 600);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: TableStrip(table: _table, me: me, busy: false, onRaise: () {}, onAnswer: (_) {}),
        ),
      ));
    }

    testWidgets('a waiting player sees the seats, their place, and the raise (no answer)', (tester) async {
      await showStrip(tester, 'me');
      expect(find.text('STARTER'), findsOneWidget);
      expect(find.text('RECEIVER'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('You play next · watching'), findsOneWidget);
      expect(find.textContaining('may rise'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the other player of the round answers the raise', (tester) async {
      await showStrip(tester, 'b');
      expect(find.text('You receive this round'), findsOneWidget);
      expect(find.textContaining('asks to raise'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
