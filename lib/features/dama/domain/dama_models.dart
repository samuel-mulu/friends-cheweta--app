/// Ethiopian Dama as sent by the server (see [DamaType] for the two rule sets).
///
/// The server decides every rule; these types only describe its state. Squares
/// are 0..63 = `row * 8 + col`, row 0 being Light's back rank. The board is a
/// 64-char string: `.` empty, `l`/`L` light man/king, `d`/`D` dark man/king.
library;

import 'package:friends_game_app/features/match/domain/turn_timing.dart';

export 'package:friends_game_app/features/match/domain/turn_timing.dart';

/// The two kinds of Dama a stake can be. Only how men capture differs; kings
/// fly and capture in every direction in both.
enum DamaType {
  /// Men capture forward only.
  egregna('DAMA_ET_FORWARD_V1', 'እግረኛ', 'ወደፊት ብቻ ይበላል', 'Men capture forward only.'),

  /// Men capture forward and backward (the classic rules).
  tankegna('DAMA_ET_V1', 'ታንከኛ', 'ወደፊት እና ወደኋላ ይበላል', 'Men capture forward and backward.');

  const DamaType(this.rulesVersion, this.name, this.hint, this.captureRule);

  /// Server rules version of stakes of this type.
  final String rulesVersion;

  /// Amharic name players know the game by.
  final String name;

  /// Short Amharic description, shown under the name.
  final String hint;

  /// How men capture, in plain English (rules sheet).
  final String captureRule;

  /// The classic rules: what every older stake and match is.
  static const fallback = DamaType.tankegna;

  /// Null for a rules version that is not a Dama type.
  static DamaType? tryParse(String? rulesVersion) {
    for (final type in values) {
      if (type.rulesVersion == rulesVersion) return type;
    }
    return null;
  }

  static DamaType parse(String? rulesVersion) => tryParse(rulesVersion) ?? fallback;
}

enum DamaColor {
  light,
  dark;

  static DamaColor parse(Object? raw) => raw?.toString().toUpperCase() == 'DARK' ? DamaColor.dark : DamaColor.light;
  DamaColor get opponent => this == DamaColor.light ? DamaColor.dark : DamaColor.light;
  String get label => this == DamaColor.light ? 'Light' : 'Dark';
}

int damaRow(int square) => square ~/ 8;
int damaCol(int square) => square % 8;

class DamaPiece {
  const DamaPiece(this.color, {this.king = false});
  final DamaColor color;
  final bool king;

  static DamaPiece? fromCell(String cell) => switch (cell) {
        'l' => const DamaPiece(DamaColor.light),
        'L' => const DamaPiece(DamaColor.light, king: true),
        'd' => const DamaPiece(DamaColor.dark),
        'D' => const DamaPiece(DamaColor.dark, king: true),
        _ => null,
      };

  String get cell => switch ((color, king)) {
        (DamaColor.light, false) => 'l',
        (DamaColor.light, true) => 'L',
        (DamaColor.dark, false) => 'd',
        (DamaColor.dark, true) => 'D',
      };

  @override
  bool operator ==(Object other) => other is DamaPiece && other.color == color && other.king == king;
  @override
  int get hashCode => Object.hash(color, king);
}

/// `path[0]` is the start square, then every landing square.
class DamaMove {
  const DamaMove({required this.path, this.captured = const []});
  final List<int> path;
  final List<int> captured;

  int get from => path.first;
  int get to => path.last;
  bool get isCapture => captured.isNotEmpty;

  factory DamaMove.fromJson(Map<String, dynamic> json) => DamaMove(
        path: _ints(json['path']),
        captured: _ints(json['captured']),
      );

  static List<DamaMove> listFrom(Object? raw) => raw is List
      ? raw.whereType<Map>().map((m) => DamaMove.fromJson(Map<String, dynamic>.from(m))).where((m) => m.path.length >= 2).toList()
      : const [];

  @override
  bool operator ==(Object other) => other is DamaMove && _same(other.path, path) && _same(other.captured, captured);
  @override
  int get hashCode => Object.hashAll([...path, -1, ...captured]);
}

class DamaPlayer {
  const DamaPlayer({required this.userId, required this.color});
  final String userId;
  final DamaColor color;
}

class DamaGame {
  const DamaGame({
    required this.matchId,
    required this.version,
    required this.finished,
    required this.players,
    required this.board,
    this.currentPlayerId,
    this.plyCount = 0,
    this.pliesSinceProgress = 0,
    this.lastMove,
    this.winnerOrder = const [],
    this.result,
    this.finishReason,
    this.type = DamaType.fallback,
  });

  /// እግረኛ or ታንከኛ (from the match's rules version).
  final DamaType type;

  final String matchId;
  final int version;
  final bool finished;
  final List<DamaPlayer> players;
  final String board;
  final String? currentPlayerId;
  final int plyCount;
  final int pliesSinceProgress;
  final DamaMove? lastMove;
  final List<String> winnerOrder;

  /// WIN | DRAW once finished.
  final String? result;

  /// NO_PIECES | NO_MOVES | RESIGN | DRAW_RULE once finished.
  final String? finishReason;

  bool get isDraw => result == 'DRAW';
  String? get winnerId => winnerOrder.isEmpty ? null : winnerOrder.first;

  DamaPiece? pieceAt(int square) => square >= 0 && square < board.length ? DamaPiece.fromCell(board[square]) : null;

  DamaColor? colorOf(String? userId) {
    for (final player in players) {
      if (player.userId == userId) return player.color;
    }
    return null;
  }

  String? playerOf(DamaColor color) {
    for (final player in players) {
      if (player.color == color) return player.userId;
    }
    return null;
  }

  int countPieces(DamaColor color) {
    var count = 0;
    for (var i = 0; i < board.length; i++) {
      if (DamaPiece.fromCell(board[i])?.color == color) count++;
    }
    return count;
  }

  /// Pieces this color has taken from the opponent (12 at the start each).
  int capturedBy(DamaColor color) => 12 - countPieces(color.opponent);

  factory DamaGame.fromJson(Map<String, dynamic> json) {
    final rawLast = json['lastMove'];
    return DamaGame(
      matchId: json['matchId']?.toString() ?? '',
      version: _int(json['version']),
      finished: json['phase']?.toString() == 'FINISHED',
      players: (json['players'] as List? ?? const [])
          .whereType<Map>()
          .map((p) => DamaPlayer(userId: p['userId']?.toString() ?? '', color: DamaColor.parse(p['color'])))
          .toList(),
      board: (json['board']?.toString() ?? '').padRight(64, '.').substring(0, 64),
      currentPlayerId: _optional(json['currentPlayerId']),
      plyCount: _int(json['plyCount']),
      pliesSinceProgress: _int(json['pliesSinceProgress']),
      lastMove: rawLast is Map ? DamaMove.fromJson(Map<String, dynamic>.from(rawLast)) : null,
      winnerOrder: (json['winnerOrder'] as List? ?? const []).map((e) => e.toString()).toList(),
      result: _optional(json['result']),
      finishReason: _optional(json['finishReason']),
      type: DamaType.parse(_optional(json['rulesVersion'])),
    );
  }

  DamaGame copyWith({
    int? version,
    bool? finished,
    String? board,
    String? currentPlayerId,
    bool clearCurrentPlayer = false,
    int? plyCount,
    int? pliesSinceProgress,
    DamaMove? lastMove,
    List<String>? winnerOrder,
    String? result,
    String? finishReason,
  }) =>
      DamaGame(
        matchId: matchId,
        version: version ?? this.version,
        finished: finished ?? this.finished,
        players: players,
        board: board ?? this.board,
        currentPlayerId: clearCurrentPlayer ? null : currentPlayerId ?? this.currentPlayerId,
        plyCount: plyCount ?? this.plyCount,
        pliesSinceProgress: pliesSinceProgress ?? this.pliesSinceProgress,
        lastMove: lastMove ?? this.lastMove,
        winnerOrder: winnerOrder ?? this.winnerOrder,
        result: result ?? this.result,
        finishReason: finishReason ?? this.finishReason,
        type: type,
      );
}

/// Dama's move clock is the shared turn clock.
typedef DamaTiming = TurnTiming;

class DamaParticipant {
  const DamaParticipant({required this.userId, required this.fullName, this.color});
  final String userId;
  final String fullName;
  final DamaColor? color;

  factory DamaParticipant.fromJson(Map<String, dynamic> json) => DamaParticipant(
        userId: json['userId']?.toString() ?? '',
        fullName: json['fullName']?.toString() ?? 'Player',
        color: json['color'] == null ? null : DamaColor.parse(json['color']),
      );

  /// First name, for compact seats and banners.
  String get shortName {
    final first = fullName.trim().split(RegExp(r'\s+')).first;
    return first.isEmpty ? 'Player' : first;
  }
}

int _int(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
String? _optional(Object? value) {
  final text = value?.toString();
  return text == null || text.isEmpty ? null : text;
}

List<int> _ints(Object? raw) => raw is List ? raw.map(_int).toList() : const [];
bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
