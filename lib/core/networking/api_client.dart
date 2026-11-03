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

  Future<String?> _refreshAccessToken() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _doRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await Dio(BaseOptions(baseUrl: _dio.options.baseUrl)).post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data ?? const <String, dynamic>{};
      final access = data['accessToken']?.toString();
      final refresh = data['refreshToken']?.toString() ?? refreshToken;
      if (access == null) return null;
      await _storage.saveTokens(accessToken: access, refreshToken: refresh);
      return access;
    } on DioException {
      await _storage.clearTokens();
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
    connectTimeout: const Duration(seconds: 45),
    receiveTimeout: const Duration(seconds: 45),
    headers: {'Accept': 'application/json'},
  ));
  return ApiClient(dio, ref.watch(secureStorageProvider));
});
