import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';
import 'package:friends_game_app/features/game_hub/domain/game_variant.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';

/// Device-level player preferences: one source of truth for the Profile
/// switches, the in-match toggles and what the lobby opens on.
class PlayerPreferences {
  const PlayerPreferences({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.fastAnimations = false,
    this.tokensToWin = 4,
    this.autoMatch = true,
    this.variantByGame = const {},
  });
  final bool soundEnabled;
  final bool hapticsEnabled;

  /// Faster dice/token presentation for experienced players (visual only).
  final bool fastAnimations;

  /// Last Ludo goal ("first to N home") chosen (offered first next time).
  final int tokensToWin;

  /// Match automatically with the next player ready at the same terms.
  final bool autoMatch;

  /// Last game type played per game (rules version by game code).
  final Map<String, String> variantByGame;

  /// The type [gameCode] opens on: the one played last, else its classic type.
  GameVariant? variantFor(String gameCode) => GameVariants.resolve(gameCode, variantByGame[gameCode]);

  PlayerPreferences copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? fastAnimations,
    int? tokensToWin,
    bool? autoMatch,
    Map<String, String>? variantByGame,
  }) =>
      PlayerPreferences(
        soundEnabled: soundEnabled ?? this.soundEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        fastAnimations: fastAnimations ?? this.fastAnimations,
        tokensToWin: tokensToWin ?? this.tokensToWin,
        autoMatch: autoMatch ?? this.autoMatch,
        variantByGame: variantByGame ?? this.variantByGame,
      );
}

class PreferencesController extends Notifier<PlayerPreferences> {
  /// Also read directly by GameSoundService at play time.
  static const soundKey = 'sound_enabled';
  static const _hapticsKey = 'haptics_enabled';
  static const _fastKey = 'ludo_fast_animations';
  static const _goalKey = 'ludo_tokens_to_win';
  static const _autoMatchKey = 'lobby_auto_match';
  static String _variantKey(String gameCode) => 'variant_${gameCode.toLowerCase()}';

  /// Before game types were shared: the Dama type alone.
  static const _legacyDamaKey = 'dama_rules_version';
  static const fastSpeed = 0.6;

  @override
  PlayerPreferences build() {
    final storage = _storage;
    final variants = <String, String>{};
    for (final gameCode in const ['LUDO', 'DAMA']) {
      final stored = storage?.getString(_variantKey(gameCode)) ?? (gameCode == 'DAMA' ? storage?.getString(_legacyDamaKey) : null);
      if (stored != null) variants[gameCode] = stored;
    }
    final prefs = PlayerPreferences(
      soundEnabled: storage?.getBool(soundKey) ?? true,
      hapticsEnabled: storage?.getBool(_hapticsKey) ?? true,
      fastAnimations: storage?.getBool(_fastKey) ?? false,
      tokensToWin: (storage?.getInt(_goalKey) ?? 4).clamp(1, 4).toInt(),
      autoMatch: storage?.getBool(_autoMatchKey) ?? true,
      variantByGame: variants,
    );
    LudoMotion.speed = prefs.fastAnimations ? fastSpeed : 1.0;
    return prefs;
  }

  Future<void> setSound(bool value) async {
    state = state.copyWith(soundEnabled: value);
    await _storage?.setBool(soundKey, value);
  }

  Future<void> setHaptics(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    await _storage?.setBool(_hapticsKey, value);
  }

  Future<void> setFastAnimations(bool value) async {
    LudoMotion.speed = value ? fastSpeed : 1.0;
    state = state.copyWith(fastAnimations: value);
    await _storage?.setBool(_fastKey, value);
  }

  Future<void> setTokensToWin(int value) async {
    state = state.copyWith(tokensToWin: value.clamp(1, 4).toInt());
    await _storage?.setInt(_goalKey, state.tokensToWin);
  }

  Future<void> setAutoMatch(bool value) async {
    if (value == state.autoMatch) return;
    state = state.copyWith(autoMatch: value);
    await _storage?.setBool(_autoMatchKey, value);
  }

  /// Remember the type played last in its game.
  Future<void> setVariant(GameVariant variant) async {
    if (state.variantByGame[variant.gameCode] == variant.rulesVersion) return;
    state = state.copyWith(variantByGame: {...state.variantByGame, variant.gameCode: variant.rulesVersion});
    await _storage?.setString(_variantKey(variant.gameCode), variant.rulesVersion);
  }

  PreferencesStorage? get _storage {
    try {
      return ref.read(preferencesStorageProvider);
    } catch (_) {
      return null; // not configured (widget tests): defaults apply
    }
  }
}

final playerPreferencesProvider = NotifierProvider<PreferencesController, PlayerPreferences>(PreferencesController.new);
