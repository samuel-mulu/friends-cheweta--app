import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';
import 'package:friends_game_app/features/dama/domain/dama_models.dart';
import 'package:friends_game_app/features/ludo/domain/ludo_motion.dart';

/// Device-level player preferences: one source of truth for the Profile
/// switches and the in-match toggles.
class PlayerPreferences {
  const PlayerPreferences({
    this.soundEnabled = true,
    this.hapticsEnabled = true,
    this.fastAnimations = false,
    this.tokensToWin = 4,
    this.damaType = DamaType.fallback,
  });
  final bool soundEnabled;
  final bool hapticsEnabled;

  /// Faster dice/token presentation for experienced players (visual only).
  final bool fastAnimations;

  /// Last "first to N home" goal chosen (offered first next time).
  final int tokensToWin;

  /// Last Dama type played (እግረኛ / ታንከኛ); the lobby and practice open on it.
  final DamaType damaType;

  PlayerPreferences copyWith({
    bool? soundEnabled,
    bool? hapticsEnabled,
    bool? fastAnimations,
    int? tokensToWin,
    DamaType? damaType,
  }) =>
      PlayerPreferences(
        soundEnabled: soundEnabled ?? this.soundEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        fastAnimations: fastAnimations ?? this.fastAnimations,
        tokensToWin: tokensToWin ?? this.tokensToWin,
        damaType: damaType ?? this.damaType,
      );
}

class PreferencesController extends Notifier<PlayerPreferences> {
  /// Also read directly by GameSoundService at play time.
  static const soundKey = 'sound_enabled';
  static const _hapticsKey = 'haptics_enabled';
  static const _fastKey = 'ludo_fast_animations';
  static const _goalKey = 'ludo_tokens_to_win';
  static const _damaTypeKey = 'dama_rules_version';
  static const fastSpeed = 0.6;

  @override
  PlayerPreferences build() {
    final storage = _storage;
    final prefs = PlayerPreferences(
      soundEnabled: storage?.getBool(soundKey) ?? true,
      hapticsEnabled: storage?.getBool(_hapticsKey) ?? true,
      fastAnimations: storage?.getBool(_fastKey) ?? false,
      tokensToWin: (storage?.getInt(_goalKey) ?? 4).clamp(1, 4).toInt(),
      damaType: DamaType.parse(storage?.getString(_damaTypeKey)),
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

  Future<void> setDamaType(DamaType value) async {
    if (value == state.damaType) return;
    state = state.copyWith(damaType: value);
    await _storage?.setString(_damaTypeKey, value.rulesVersion);
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
