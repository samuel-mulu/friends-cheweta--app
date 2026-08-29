import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:friends_game_app/core/storage/preferences_storage.dart';

class SecureStorage {
  SecureStorage(this._storage, this._preferences);

  final FlutterSecureStorage _storage;
  final PreferencesStorage _preferences;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  Future<String?> readAccessToken() {
    if (kIsWeb) return Future.value(_preferences.getString(_accessTokenKey));
    return _storage.read(key: _accessTokenKey);
  }

  Future<String?> readRefreshToken() {
    if (kIsWeb) return Future.value(_preferences.getString(_refreshTokenKey));
    return _storage.read(key: _refreshTokenKey);
  }

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    if (kIsWeb) {
      await Future.wait([
        _preferences.setString(_accessTokenKey, accessToken),
        _preferences.setString(_refreshTokenKey, refreshToken),
      ]);
      return;
    }

    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  Future<void> clearTokens() async {
    if (kIsWeb) {
      await Future.wait([
        _preferences.remove(_accessTokenKey),
        _preferences.remove(_refreshTokenKey),
      ]);
      return;
    }

    await Future.wait([
      _storage.delete(key: _accessTokenKey),
      _storage.delete(key: _refreshTokenKey),
    ]);
  }
}

final secureStorageProvider = Provider<SecureStorage>((ref) {
  return SecureStorage(
    const FlutterSecureStorage(
      webOptions: WebOptions(
        dbName: 'friends_game_secure',
        publicKey: 'friends_game_public_key',
      ),
    ),
    ref.watch(preferencesStorageProvider),
  );
});
