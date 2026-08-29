import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesStorage {
  PreferencesStorage._(this._preferences);

  final SharedPreferences _preferences;

  static Future<PreferencesStorage> create() async {
    return PreferencesStorage._(await SharedPreferences.getInstance());
  }

  String? getString(String key) => _preferences.getString(key);
  bool? getBool(String key) => _preferences.getBool(key);
  Future<bool> setString(String key, String value) => _preferences.setString(key, value);
  Future<bool> setBool(String key, bool value) => _preferences.setBool(key, value);
  Future<bool> remove(String key) => _preferences.remove(key);
}

final preferencesStorageProvider = Provider<PreferencesStorage>((ref) {
  throw StateError('PreferencesStorage must be overridden in bootstrap().');
});
