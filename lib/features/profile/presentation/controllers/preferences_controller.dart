import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';

class PlayerPreferences {
  const PlayerPreferences({this.soundEnabled = true, this.hapticsEnabled = true});
  final bool soundEnabled;
  final bool hapticsEnabled;
  PlayerPreferences copyWith({bool? soundEnabled, bool? hapticsEnabled}) => PlayerPreferences(soundEnabled: soundEnabled ?? this.soundEnabled, hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled);
}

class PreferencesController extends Notifier<PlayerPreferences> {
  static const _soundKey = 'sound_enabled';
  static const _hapticsKey = 'haptics_enabled';

  @override
  PlayerPreferences build() {
    final storage = ref.read(preferencesStorageProvider);
    return PlayerPreferences(
      soundEnabled: storage.getBool(_soundKey) ?? true,
      hapticsEnabled: storage.getBool(_hapticsKey) ?? true,
    );
  }

  Future<void> setSound(bool value) async {
    state = state.copyWith(soundEnabled: value);
    await ref.read(preferencesStorageProvider).setBool(_soundKey, value);
  }

  Future<void> setHaptics(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    await ref.read(preferencesStorageProvider).setBool(_hapticsKey, value);
  }
}

final playerPreferencesProvider = NotifierProvider<PreferencesController, PlayerPreferences>(PreferencesController.new);
