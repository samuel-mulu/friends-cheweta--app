import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';

/// Last good server responses, so screens open instantly with known data and
/// refresh quietly. Only non-secret display data belongs here (never tokens).
class JsonCache {
  const JsonCache(this._preferences);
  final PreferencesStorage _preferences;

  static const _prefix = 'cache.v1.';

  Object? read(String key) {
    final raw = _preferences.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, Object? value) async {
    try {
      await _preferences.setString('$_prefix$key', jsonEncode(value));
    } catch (_) {
      // A cache that cannot be written is only a slower start.
    }
  }

  Future<void> remove(String key) => _preferences.remove('$_prefix$key');
}

final jsonCacheProvider = Provider<JsonCache>((ref) => JsonCache(ref.watch(preferencesStorageProvider)));
