import 'package:friends_game_app/features/ludo/domain/ludo_visual_models.dart';

/// Progress thresholds for one rules version. Progress is player-relative:
/// -1 = yard, `0..trackLast` = shared track, `homeStart..homeLast` = private
/// home column, `finish` = home. The shared loop always has [trackLength]
/// cells; a colour visits only [lapSquares] of them before turning in.
///
/// The server sends the resolved spec with every snapshot; when it is absent
/// (older servers) it is derived from the rules version.
class LudoBoardSpec {
  const LudoBoardSpec({required this.trackLength, required this.lapSquares, required this.homeColumnLength});

  final int trackLength;
  final int lapSquares;
  final int homeColumnLength;

  int get trackLast => lapSquares - 1;
  int get homeStart => lapSquares;
  int get homeLast => homeStart + homeColumnLength - 1;
  int get finish => homeLast + 1;

  /// Matches created under V1/V2 walked one square past the home door.
  static const legacy = LudoBoardSpec(trackLength: 52, lapSquares: 52, homeColumnLength: 5);

  /// Standard board (V3+): 51 shared squares per colour, finish at 56.
  static const standard = LudoBoardSpec(trackLength: 52, lapSquares: 51, homeColumnLength: 5);

  static const safeGlobalSquares = <int>{0, 8, 13, 21, 26, 34, 39, 47};

  factory LudoBoardSpec.fromRulesVersion(String? rulesVersion) => switch (rulesVersion) {
        'LUDO_CLASSIC_V1' || 'LUDO_CLASSIC_V2' => legacy,
        _ => standard,
      };

  /// The `board` object of a join/sync ack, or null when the server did not send one.
  static LudoBoardSpec? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final track = int.tryParse(raw['trackLength']?.toString() ?? '');
    final lap = int.tryParse(raw['lapSquares']?.toString() ?? '');
    final home = int.tryParse(raw['homeColumnLength']?.toString() ?? '');
    if (track == null || lap == null || home == null || lap <= 0 || lap > track || home <= 0) return null;
    return LudoBoardSpec(trackLength: track, lapSquares: lap, homeColumnLength: home);
  }

  bool isBase(int progress) => progress < 0;
  bool isTrack(int progress) => progress >= 0 && progress <= trackLast;
  bool isHome(int progress) => progress >= homeStart && progress <= homeLast;
  bool isFinished(int progress) => progress >= finish;

  /// Shared-track cell index for a colour's progress, or null off the track.
  int? globalSquare(LudoColor color, int progress) =>
      isTrack(progress) ? (color.startIndex + progress) % trackLength : null;

  bool isSafe(LudoColor color, int progress) {
    final square = globalSquare(color, progress);
    return square != null && safeGlobalSquares.contains(square);
  }

  @override
  bool operator ==(Object other) =>
      other is LudoBoardSpec &&
      other.trackLength == trackLength &&
      other.lapSquares == lapSquares &&
      other.homeColumnLength == homeColumnLength;

  @override
  int get hashCode => Object.hash(trackLength, lapSquares, homeColumnLength);

  @override
  String toString() => 'LudoBoardSpec(lap $lapSquares, home $homeStart..$homeLast, finish $finish)';
}
