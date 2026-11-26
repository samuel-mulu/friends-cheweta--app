import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/config/app_config.dart';
import 'package:friends_game_app/core/networking/api_exception.dart';
import 'package:friends_game_app/core/storage/secure_storage.dart';

class ApiClient {
  ApiClient(this._dio, this._storage);

  final Dio _dio;
  final SecureStorage _storage;
  Future<String?>? _refreshInFlight;

  Dio get dio => _dio;

  /// A fresh access token (shared by concurrent callers), or null when the
  /// session is over. Used by HTTP on a 401 and by the socket before it connects.
  Future<String?> refreshAccessToken() => _refreshAccessToken();

  Future<String?> _refreshAccessToken() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _doRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  /// New access token, or null when the server rejected the refresh token
  /// (the session is over). Network failures are rethrown instead: a phone
  /// that is offline must not lose its session.
  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: _dio.options.connectTimeout,
        receiveTimeout: _dio.options.receiveTimeout,
        headers: const {'Accept': 'application/json'},
      )).post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data ?? const <String, dynamic>{};
      final access = data['accessToken']?.toString();
      final refresh = data['refreshToken']?.toString() ?? refreshToken;
      if (access == null) return null;
      await _storage.saveTokens(accessToken: access, refreshToken: refresh);
      return access;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == null || status >= 500) throw mapDioException(error); // offline or server trouble
      await _storage.clearTokens(); // refresh token rejected
      return null;
    }
  }

  Future<Response<T>> request<T>(
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool authenticated = true,
  }) async {
    Future<Response<T>> send(String? token) {
      return _dio.request<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, headers: authenticated && token != null ? {'Authorization': 'Bearer $token'} : null),
      );
    }

    try {
      final token = authenticated ? await _storage.readAccessToken() : null;
      return await send(token);
    } on DioException catch (error) {
      if (authenticated && error.response?.statusCode == 401 && path != '/auth/refresh') {
        final refreshed = await _refreshAccessToken();
        if (refreshed != null) {
          try {
            return await send(refreshed);
          } on DioException catch (retryError) {
            throw mapDioException(retryError);
          }
        }
      }
      throw mapDioException(error);
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.current.apiBaseUrl,
    // A sleeping free-tier server can take ~30-50 s to wake up; screens show
    // their own progress, and start-up never waits on this (see AuthController).
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 45),
    headers: {'Accept': 'application/json'},
  ));
  return ApiClient(dio, ref.watch(secureStorageProvider));
});
