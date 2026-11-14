import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_board_spec.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_match_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';
import 'support/ludo_fixtures.dart';

void main() {
  group('LudoBoardSpec', () {
    test('V3 is the standard board: 51 shared squares, home 51..55, finish 56', () {
      final board = LudoBoardSpec.fromRulesVersion('LUDO_CLASSIC_V3');
      expect(board, LudoBoardSpec.standard);
      expect((board.trackLast, board.homeStart, board.homeLast, board.finish), (50, 51, 55, 56));
      expect(board.isTrack(50), isTrue);
      expect(board.isTrack(51), isFalse);
      expect(board.isHome(51), isTrue);
      expect(board.isFinished(56), isTrue);
      expect(board.globalSquare(LudoColor.red, 51), isNull);
    });

    test('V1/V2 keep the legacy 52-square lap for matches already stored', () {
      for (final version in ['LUDO_CLASSIC_V1', 'LUDO_CLASSIC_V2']) {
        final board = LudoBoardSpec.fromRulesVersion(version);
        expect(board, LudoBoardSpec.legacy);
        expect((board.trackLast, board.homeStart, board.finish), (51, 52, 57));
        expect(board.globalSquare(LudoColor.red, 51), 51);
      }
    });

    test('unknown or missing versions default to the standard board', () {
      expect(LudoBoardSpec.fromRulesVersion(null), LudoBoardSpec.standard);
      expect(LudoBoardSpec.fromRulesVersion('LUDO_CLASSIC_V9'), LudoBoardSpec.standard);
    });

    test('parses the server spec and rejects garbage', () {
      expect(LudoBoardSpec.tryParse({'trackLength': 52, 'lapSquares': 51, 'homeColumnLength': 5}), LudoBoardSpec.standard);
      expect(LudoBoardSpec.tryParse({'trackLength': 52}), isNull);
      expect(LudoBoardSpec.tryParse('nope'), isNull);
    });

    test('safe squares are the four starts and the star eight after each', () {
      final board = LudoBoardSpec.standard;
      expect(board.isSafe(LudoColor.red, 0), isTrue);
      expect(board.isSafe(LudoColor.red, 8), isTrue);
      expect(board.isSafe(LudoColor.green, 0), isTrue); // global 13
      expect(board.isSafe(LudoColor.red, 9), isFalse);
      expect(board.isSafe(LudoColor.red, 52), isFalse); // home lane is private, not "safe"
    });
  });

  group('geometry follows the board spec', () {
    const size = 150.0; // 10 px cells
    Offset at(LudoColor color, int progress, LudoBoardSpec board) =>
        LudoBoardGeometry.tokenCenter(color: color, progress: progress, baseIndex: 0, boardSize: size, board: board);

    test('RED progress 50 is the door square (7,0) on every board', () {
      for (final board in [LudoBoardSpec.standard, LudoBoardSpec.legacy]) {
        expect(at(LudoColor.red, 50, board), const Offset(5, 75)); // column 0, row 7
      }
    });

    test('V3: progress 51 is the first home cell (7,1); V2: the square before RED\'s start (6,0)', () {
      expect(at(LudoColor.red, 51, LudoBoardSpec.standard), const Offset(15, 75)); // column 1, row 7
      expect(at(LudoColor.red, 51, LudoBoardSpec.legacy), const Offset(5, 65)); // column 0, row 6
      expect(at(LudoColor.red, 52, LudoBoardSpec.legacy), const Offset(15, 75)); // legacy first home cell
    });

    test('the walk from the door never touches (6,0) on the standard board', () {
      final cells = [for (var p = 50; p <= 56; p++) at(LudoColor.red, p, LudoBoardSpec.standard)];
      expect(cells, isNot(contains(const Offset(5, 65))));
    });

    test('occupancy keys share the track but keep home lanes private', () {
      expect(
        LudoBoardGeometry.occupancyKey(color: LudoColor.red, progress: 13, tokenId: 'a'),
        LudoBoardGeometry.occupancyKey(color: LudoColor.green, progress: 0, tokenId: 'b'),
      );
      expect(LudoBoardGeometry.occupancyKey(color: LudoColor.red, progress: 51, tokenId: 'a'), 'home-red-51');
      expect(LudoBoardGeometry.occupancyKey(color: LudoColor.red, progress: 56, tokenId: 'a'), 'finish-red');
    });
  });

  test('a snapshot carries its board; the server spec wins over the rules version', () {
    final v2 = snapshotWith(rulesVersion: 'LUDO_CLASSIC_V2');
    expect(v2.board, LudoBoardSpec.legacy);
    expect(snapshotWith().board, LudoBoardSpec.standard);
    expect(snapshotWith(red: [51, -1]).copyWith().board, LudoBoardSpec.standard);
  });

  test('the server path is animated when present, else derived', () {
    final event = moveEvent(playerId: 'me', tokenId: 'RED-1', color: 'RED', from: 50, to: 53, dice: 3);
    final withPath = LudoMoveResolution.fromJson(Map<String, dynamic>.from(event.data['move'] as Map));
    expect(withPath.path, [50, 51, 52, 53]);
    expect(LudoMotion.path(withPath), [50, 51, 52, 53]);
    expect(LudoMotion.steps(withPath), 3);

    final legacyJson = Map<String, dynamic>.from(event.data['move'] as Map)..remove('move');
    final withoutPath = LudoMoveResolution.fromJson(legacyJson);
    expect(withoutPath.path, isEmpty);
    expect(LudoMotion.path(withoutPath), [50, 51, 52, 53]);
  });
}
