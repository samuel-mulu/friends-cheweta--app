/// A game type a stake can be, as players know it. The server keys every
/// rule off the stake's rules version; this only names and explains it.
///
/// Add a game's types here and the lobby (type cards, badges, stake lists),
/// practice, requests and match screens pick them up.
class GameVariant {
  const GameVariant({
    required this.gameCode,
    required this.rulesVersion,
    required this.name,
    required this.hint,
    required this.rule,
    this.isDefault = false,
  });

  /// LUDO, DAMA, …
  final String gameCode;

  /// The server rules version of stakes of this type.
  final String rulesVersion;

  /// Amharic name players know it by.
  final String name;

  /// Short Amharic description under the name.
  final String hint;

  /// What differs, in plain English (rules sheets, requests).
  final String rule;

  /// The classic type: what older stakes and matches are, and the first-time choice.
  final bool isDefault;

  @override
  bool operator ==(Object other) => other is GameVariant && other.rulesVersion == rulesVersion;

  @override
  int get hashCode => rulesVersion.hashCode;

  @override
  String toString() => 'GameVariant($rulesVersion)';
}

abstract final class GameVariants {
  // Dama: only how men capture differs; kings are the same.
  static const damaForward = GameVariant(
    gameCode: 'DAMA',
    rulesVersion: 'DAMA_ET_FORWARD_V1',
    name: 'እግረኛ',
    hint: 'ወደፊት ብቻ ይበላል',
    rule: 'Men capture forward only.',
  );
  static const damaClassic = GameVariant(
    gameCode: 'DAMA',
    rulesVersion: 'DAMA_ET_V1',
    name: 'ታንከኛ',
    hint: 'ወደፊት እና ወደኋላ ይበላል',
    rule: 'Men capture forward and backward.',
    isDefault: true,
  );

  // Ludo: what happens when a token lands on an opponent.
  static const ludoClassic = GameVariant(
    gameCode: 'LUDO',
    rulesVersion: 'LUDO_CLASSIC_V3',
    name: 'መመለስ ያለበት',
    hint: 'የተመታ ወደ ቤቱ ይመለሳል',
    rule: 'Landing on an opponent sends it back home.',
    isDefault: true,
  );
  static const ludoNoCapture = GameVariant(
    gameCode: 'LUDO',
    rulesVersion: 'LUDO_NO_CAPTURE_V1',
    name: 'መመለስ የሌለበት',
    hint: 'ማንም ወደ ቤቱ አይመለስም',
    rule: 'Nobody is sent home: tokens can share a square.',
  );
  static const ludoMissedCapture = GameVariant(
    gameCode: 'LUDO',
    rulesVersion: 'LUDO_MISSED_CAPTURE_V1',
    name: 'መመለስ የረሳ ይሸነፋል',
    hint: 'መመለስ እየቻለ የተወ ይሸነፋል',
    rule: 'If you can send a token home but move another, you lose the match.',
  );

  // Karta: a 1v1 match, or a queue table where the round winner keeps dealing.
  static const kartaClassic = GameVariant(
    gameCode: 'KARTA',
    rulesVersion: 'KARTA_LATLAT_V1',
    name: 'ሁለት ለሁለት',
    hint: 'መጀመሪያ 3 ዙር ያሸነፈ',
    rule: 'One opponent: the first to win 3 rounds takes the pot.',
    isDefault: true,
  );
  static const kartaTable = GameVariant(
    gameCode: 'KARTA',
    rulesVersion: 'KARTA_TABLE_V1',
    name: 'ጠረጴዛ',
    hint: 'ያሸነፈ ያከፋፍላል፣ ዙሩ ወዲያው ይከፈላል',
    rule: 'Up to 4 at a table. Each round is 1v1 and pays at once; the winner keeps dealing and the next in line plays.',
  );

  static const _byGame = <String, List<GameVariant>>{
    'DAMA': [damaForward, damaClassic],
    'LUDO': [ludoClassic, ludoNoCapture, ludoMissedCapture],
    'KARTA': [kartaClassic, kartaTable],
  };

  /// A game's types in the order players see them (empty: the game has none).
  static List<GameVariant> of(String gameCode) => _byGame[gameCode] ?? const [];

  /// The type of a rules version; null for a version that isn't a named type.
  static GameVariant? find(String? rulesVersion) {
    if (rulesVersion == null) return null;
    for (final variants in _byGame.values) {
      for (final variant in variants) {
        if (variant.rulesVersion == rulesVersion) return variant;
      }
    }
    return null;
  }

  /// The classic type of [gameCode] (null when the game has no types).
  static GameVariant? defaultOf(String gameCode) {
    for (final variant in of(gameCode)) {
      if (variant.isDefault) return variant;
    }
    return null;
  }

  /// [find], else the game's classic type (older matches and stakes).
  static GameVariant? resolve(String gameCode, String? rulesVersion) {
    final found = find(rulesVersion);
    return found != null && found.gameCode == gameCode ? found : defaultOf(gameCode);
  }
}
