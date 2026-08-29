import 'package:flutter_test/flutter_test.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';
import 'package:friends_game_app/features/ludo/presentation/widgets/ludo_board_geometry.dart';

void main() {
  test('board uses the backend canonical 52-cell track and safe-square map', () {
    expect(LudoBoardGeometry.track.length, 52);
    expect(LudoBoardGeometry.safeGlobalSquares, {0, 8, 13, 21, 26, 34, 39, 47});
    expect(LudoColor.red.startIndex, 0);
    expect(LudoColor.green.startIndex, 13);
    expect(LudoColor.yellow.startIndex, 26);
    expect(LudoColor.blue.startIndex, 39);
  });

  test('each color exposes five visible home-path cells', () {
    for (final color in LudoColor.values) {
      expect(LudoBoardGeometry.homePaths[color]?.length, 5);
    }
  });
}
