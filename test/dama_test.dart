import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/core/audio/game_sound_service.dart';
import 'package:friends_game_app/core/socket/game_socket_service.dart';
import 'package:friends_game_app/core/socket/realtime_event.dart';
import 'package:friends_game_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:friends_game_app/features/chat/application/match_chat_controller.dart';
import 'package:friends_game_app/features/dama/application/dama_event_reducer.dart';
import 'package:friends_game_app/features/dama/application/dama_match_controller.dart';
import 'package:friends_game_app/features/dama/application/dama_selection.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/dama/presentation/dama_presenter.dart';
import 'package:friends_game_app/features/dama/presentation/screens/dama_match_screen.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_board.dart';
import 'package:friends_game_app/features/dama/presentation/widgets/dama_paint.dart';
import 'support/fake_socket.dart';

/// "c3" → square (a1 = 0).
int sq(String name) => (int.parse(name.substring(1)) - 1) * 8 + (name.codeUnitAt(0) - 97);

String startBoard() => List.generate(64, (i) {
      final row = i ~/ 8;
      if ((row + i % 8).isOdd) return '.';
      return row <= 2 ? 'l' : (row >= 5 ? 'd' : '.');
    }).join();

String boardWith(Map<String, String> pieces) {
  final cells = List.filled(64, '.');
  pieces.forEach((name, cell) => cells[sq(name)] = cell);
  return cells.join();
}

DamaMove mv(List<String> path, [List<String> captured = const []]) =>
    DamaMove(path: path.map(sq).toList(), captured: captured.map(sq).toList());

Map<String, dynamic> moveJson(DamaMove m) => {'path': m.path, 'captured': m.captured};

Map<String, dynamic> snapshotAck({
  String board = '',
  String current = 'me',
  String meColor = 'LIGHT',
  List<DamaMove> legal = const [],
  int version = 0,
}) =>
    {
      'ok': true,
      'version': version,
      'state': {
        'game': {
          'matchId': 'm1',
          'version': version,
          'phase': 'PLAYING',
          'players': [
            {'userId': meColor == 'LIGHT' ? 'me' : 'opp', 'color': 'LIGHT'},
            {'userId': meColor == 'LIGHT' ? 'opp' : 'me', 'color': 'DARK'},
          ],
          'board': board.isEmpty ? startBoard() : board,
          'currentPlayerId': current,
          'plyCount': version,
          'pliesSinceProgress': 0,
          'lastMove': null,
          'winnerOrder': [],
          'result': null,
          'finishReason': null,
        },
      },
      'timing': {'version': version, 'playerId': current, 'turnEndsAt': null, 'strikes': {}, 'maxStrikes': 3},
      'participants': [
        {'userId': 'me', 'fullName': 'Me Player', 'color': meColor},
        {'userId': 'opp', 'fullName': 'Abebe Kebede', 'color': meColor == 'LIGHT' ? 'DARK' : 'LIGHT'},
      ],
      'legalMoves': [for (final m in legal) moveJson(m)],
    };

void main() {
  group('picker', () {
    final quiet = [mv(['c3', 'b4']), mv(['c3', 'd4']), mv(['e3', 'd4']), mv(['e3', 'f4'])];

    test('pick a piece, then a destination sends that move', () {
      var r = DamaPicker.tap(quiet, DamaSelection.none, sq('c3'));
      expect(r.selection.from, sq('c3'));
      expect(DamaPicker.targets(quiet, r.selection), {sq('b4'), sq('d4')});
      r = DamaPicker.tap(quiet, r.selection, sq('d4'));
      expect(r.send, mv(['c3', 'd4']));
      expect(r.selection.isEmpty, isTrue);
    });

    test('tapping another movable piece switches; an empty square clears', () {
      var r = DamaPicker.tap(quiet, DamaSelection(from: sq('c3')), sq('e3'));
      expect(r.selection.from, sq('e3'));
      r = DamaPicker.tap(quiet, r.selection, sq('h8'));
      expect(r.selection.isEmpty, isTrue);
      expect(r.send, isNull);
    });

    test('a single movable piece (forced capture) is picked for you', () {
      final forced = [mv(['c3', 'e5'], ['d4'])];
      expect(DamaPicker.initial(forced).from, sq('c3'));
      expect(DamaPicker.initial(quiet).isEmpty, isTrue);
    });

    test('routes that split are chosen landing by landing', () {
      // A king with two 2-capture routes sharing the first landing.
      final routes = [mv(['a1', 'f6', 'd8'], ['d4', 'e7']), mv(['a1', 'f6', 'h4'], ['d4', 'g5'])];
      var r = DamaPicker.tap(routes, DamaSelection.none, sq('a1'));
      expect(DamaPicker.targets(routes, r.selection), containsAll([sq('d8'), sq('h4'), sq('f6')]));
      // Tapping a final square directly plays it when only one route ends there.
      expect(DamaPicker.tap(routes, r.selection, sq('h4')).send, routes[1]);
      // Tapping the shared first landing narrows down but does not send yet.
      r = DamaPicker.tap(routes, r.selection, sq('f6'));
      expect(r.send, isNull);
      expect(r.selection.steps, [sq('f6')]);
      expect(DamaPicker.tap(routes, r.selection, sq('d8')).send, routes[0]);
    });
  });

  group('reducer', () {
    test('a capture removes the jumped pieces; reaching the far row crowns', () {
      final game = DamaGame.fromJson((snapshotAck(board: boardWith({'d6': 'l', 'e7': 'd', 'g7': 'd', 'a7': 'd'}))['state'] as Map)['game']);
      final capture = mv(['d6', 'f8', 'h6'], ['e7', 'g7']);
      final after = reduceDamaEvent(
        game,
        RealtimeEvent(name: 'dama:piece_moved', payload: {'data': {'playerId': 'me', 'move': moveJson(capture), 'promoted': false}}),
        1,
      );
      expect(after.pieceAt(sq('h6')), const DamaPiece(DamaColor.light));
      expect(after.pieceAt(sq('e7')), isNull);
      expect(after.pieceAt(sq('g7')), isNull);
      expect(after.currentPlayerId, 'opp');
      expect(after.capturedBy(DamaColor.light), 12 - 1);

      expect(applyDamaMove(boardWith({'c7': 'l'}), mv(['c7', 'd8']), promoted: true), boardWith({'d8': 'L'}));
    });

    test('match finished carries the result', () {
      final game = DamaGame.fromJson((snapshotAck()['state'] as Map)['game']);
      final done = reduceDamaEvent(
        game,
        const RealtimeEvent(name: 'match:finished', payload: {'data': {'winnerOrder': [], 'result': 'DRAW', 'reason': 'DRAW_RULE'}}),
        9,
      );
      expect(done.finished, isTrue);
      expect(done.isDraw, isTrue);
      expect(done.currentPlayerId, isNull);
    });
  });

  group('controller', () {
    late FakeSocket socket;
    late ProviderContainer container;
    setUp(() {
      socket = FakeSocket();
      container = ProviderContainer(overrides: [gameSocketServiceProvider.overrideWithValue(socket)]);
    });
    tearDown(() => container.dispose());

    test('joins, sends the chosen path, and applies one command\'s events in order', () async {
      Map<String, dynamic>? sentMove;
      socket.reply = (event, payload) {
        if (event == 'dama:move') sentMove = payload;
        return event == 'dama:join' ? snapshotAck(legal: [mv(['c3', 'd4'])]) : {'ok': true};
      };
      final controller = container.read(damaMatchControllerProvider.notifier);
      await controller.join('m1');
      expect(container.read(damaMatchControllerProvider).legalMoves, [mv(['c3', 'd4'])]);

      expect(await controller.move(mv(['c3', 'd4'])), isTrue);
      expect(sentMove?['path'], [sq('c3'), sq('d4')]);
      expect(sentMove?['expectedVersion'], 0);

      socket.push('dama:piece_moved', {'playerId': 'me', 'move': moveJson(mv(['c3', 'd4'])), 'promoted': false}, matchId: 'm1', version: 1);
      socket.push('dama:turn_started', {'playerId': 'opp', 'legalMoves': [moveJson(mv(['f6', 'e5']))]}, matchId: 'm1', version: 1);
      await Future<void>.delayed(Duration.zero);
      final state = container.read(damaMatchControllerProvider);
      expect(state.game?.version, 1);
      expect(state.game?.pieceAt(sq('d4'))?.color, DamaColor.light);
      expect(state.game?.currentPlayerId, 'opp');
      expect(state.legalMoves, [mv(['f6', 'e5'])]);
    });

    test('a missed event (version gap) resyncs from the server', () async {
      socket.reply = (event, payload) => event == 'dama:join' ? snapshotAck() : {'ok': true};
      await container.read(damaMatchControllerProvider.notifier).join('m1');
      socket.sent.clear();
      socket.push('dama:turn_started', {'playerId': 'me'}, matchId: 'm1', version: 3);
      await Future<void>.delayed(Duration.zero);
      expect(socket.sent, contains('dama:join'));
    });

    test('an unknown outcome triggers a resync and a readable message', () async {
      socket.reply = (event, payload) => event == 'dama:join' ? snapshotAck(legal: [mv(['c3', 'd4'])]) : {'ok': false, 'code': 'ACK_TIMEOUT'};
      final controller = container.read(damaMatchControllerProvider.notifier);
      await controller.join('m1');
      socket.sent.clear();
      expect(await controller.move(mv(['c3', 'd4'])), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(socket.sent, containsAllInOrder(['dama:move', 'dama:join']));
      expect(damaErrorMessage({'code': 'ACK_TIMEOUT'}), 'Slow connection. Syncing the board…');
      expect(damaErrorMessage({'code': 'NOT_PLAYER_TURN'}), 'It is not your turn.');
    });
  });

  group('presenter', () {
    DamaMatchViewState stateFrom(Map<String, dynamic> ack) {
      final game = DamaGame.fromJson(Map<String, dynamic>.from((ack['state'] as Map)['game'] as Map));
      return DamaMatchViewState(
        matchId: 'm1',
        game: game,
        participants: (ack['participants'] as List).map((p) => DamaParticipant.fromJson(Map<String, dynamic>.from(p as Map))).toList(),
        legalMoves: DamaMove.listFrom(ack['legalMoves']),
      );
    }

    test('names the turn, the compulsory capture and the opponent', () {
      final mine = DamaPresenter(match: stateFrom(snapshotAck(legal: [mv(['c3', 'e5', 'g7'], ['d4', 'f6'])])), me: 'me');
      expect(mine.banner, 'CAPTURE 2!');
      expect(mine.mustCapture, isTrue);
      expect(mine.flipped, isFalse);
      final theirs = DamaPresenter(match: stateFrom(snapshotAck(current: 'opp', meColor: 'DARK')), me: 'me');
      expect(theirs.banner, "ABEBE'S MOVE");
      expect(theirs.flipped, isTrue); // Dark sees the board turned
      expect(theirs.legal, isEmpty);
      expect(theirs.tapExplanation, 'Wait for your turn.');
    });
  });

  test('board geometry maps taps back to squares for both orientations', () {
    for (final flipped in [false, true]) {
      final g = DamaBoardGeometry(size: 400, flipped: flipped);
      for (final square in [0, 9, 27, 54, 63]) {
        expect(g.squareAt(g.center(square)), square);
      }
    }
    // Light's own back rank is at the bottom; Dark's is at the bottom when flipped.
    expect(const DamaBoardGeometry(size: 400, flipped: false).center(0).dy, greaterThan(300));
    expect(const DamaBoardGeometry(size: 400, flipped: true).center(63).dy, greaterThan(300));
  });

  testWidgets('the match screen fits a small phone and a board tap sends the move', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final socket = FakeSocket();
    Map<String, dynamic>? sentMove;
    socket.reply = (event, payload) {
      if (event == 'dama:move') sentMove = payload;
      return event == 'dama:join' ? snapshotAck(legal: [mv(['c3', 'e5'], ['d4'])], board: boardWith({'c3': 'l', 'd4': 'd', 'h8': 'd'})) : {'ok': true};
    };
    await tester.pumpWidget(ProviderScope(
      overrides: [
        gameSocketServiceProvider.overrideWithValue(socket),
        authControllerProvider.overrideWith(SignedInAs.new),
        matchChatControllerProvider.overrideWith(_QuietChat.new),
        gameSoundServiceProvider.overrideWithValue(GameSoundService(null)),
      ],
      child: const MaterialApp(home: DamaMatchScreen(matchId: 'm1')),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('CAPTURE!'), findsOneWidget);
    expect(find.text('Capture is compulsory.'), findsOneWidget);

    // No move hints: nothing is pre-selected, so a landing square alone does nothing.
    final board = find.byType(DamaBoard);
    final rect = tester.getRect(board);
    final geometry = DamaBoardGeometry(size: rect.width, flipped: false);
    await tester.tapAt(rect.topLeft + geometry.center(sq('e5')));
    await tester.pump();
    expect(sentMove, isNull);

    // The player picks the piece, then where it goes.
    await tester.tapAt(rect.topLeft + geometry.center(sq('c3')));
    await tester.pump();
    await tester.tapAt(rect.topLeft + geometry.center(sq('e5')));
    await tester.pump();
    expect(sentMove?['path'], [sq('c3'), sq('e5')]);
    await tester.pump(const Duration(seconds: 2)); // let the tap nudge expire
  });
}

class _QuietChat extends MatchChatController {
  @override
  Future<void> load(String matchId) async {}
}
