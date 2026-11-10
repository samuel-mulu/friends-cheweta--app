import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';

/// Session storage: tokens in the platform keystore, the signed-in profile in
/// preferences (not secret; it lets the app open instantly, even offline).
///
/// Never throws. On Android the keystore can become unreadable (reinstall,
/// restored backup, OS update); a stuck read used to leave the app on the
/// splash forever. Any failure now wipes the broken entries and reads as
/// "signed out", so the worst case is signing in again.
class SecureStorage {
  SecureStorage(this._storage, this._preferences);

  final FlutterSecureStorage _storage;
  final PreferencesStorage _preferences;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userKey = 'session_user';

  /// A keystore call that hangs is treated like a failure.
  static const _timeout = Duration(seconds: 3);

  Future<String?> readAccessToken() => _read(_accessTokenKey);
  Future<String?> readRefreshToken() => _read(_refreshTokenKey);

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _write(_accessTokenKey, accessToken);
    await _write(_refreshTokenKey, refreshToken);
  }

  Future<void> clearTokens() async {
    await _delete(_accessTokenKey);
    await _delete(_refreshTokenKey);
    await _preferences.remove(_userKey);
  }

  /// Last signed-in profile (JSON), if any.
  Map<String, dynamic>? readCachedUser() {
    final raw = _preferences.getString(_userKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUser(Map<String, dynamic> user) => _preferences.setString(_userKey, jsonEncode(user));

  Future<String?> _read(String key) async {
    if (kIsWeb) return _preferences.getString(key);
    try {
      return await _storage.read(key: key).timeout(_timeout);
    } catch (error) {
      debugPrint('secure_storage_read_failed key=$key error=$error');
      await _wipe();
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      await _preferences.setString(key, value);
      return;
    }
    try {
      await _storage.write(key: key, value: value).timeout(_timeout);
    } catch (error) {
      // Start over with a clean store once, then give up quietly (the user
      // stays signed in for this run; they may need to sign in next time).
      debugPrint('secure_storage_write_failed key=$key error=$error');
      await _wipe();
      try {
        await _storage.write(key: key, value: value).timeout(_timeout);
      } catch (_) {}
    }
  }

  Future<void> _delete(String key) async {
    if (kIsWeb) {
      await _preferences.remove(key);
      return;
    }
    try {
      await _storage.delete(key: key).timeout(_timeout);
    } catch (_) {
      await _wipe();
    }
  }

  Future<void> _wipe() async {
    try {
      await _storage.deleteAll().timeout(_timeout);
    } catch (_) {}
  }
}

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage(
    const FlutterSecureStorage(
      // Undecryptable data is deleted by the plugin instead of failing.
      aOptions: AndroidOptions(resetOnError: true),
      webOptions: WebOptions(dbName: 'friends_game_secure', publicKey: 'friends_game_public_key'),
    ),
    ref.watch(preferencesStorageProvider),
  );
});
