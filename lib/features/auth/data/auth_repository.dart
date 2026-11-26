import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends_game_app/core/networking/api_client.dart';
import 'package:friends_game_app/features/auth/domain/auth_session.dart';
import 'package:friends_game_app/features/auth/domain/user.dart';

class AuthRepository {
  AuthRepository(this._api);
  final ApiClient _api;

  Future<AuthSession> login({required String phoneNumber, required String password}) async {
    final response = await _api.request<Map<String, dynamic>>('/auth/login', method: 'POST', authenticated: false, data: {
      'phoneNumber': phoneNumber.trim(),
      'password': password,
      'deviceName': 'Flutter',
    });
    return AuthSession.fromJson(response.data!);
  }

  Future<AuthSession> register({required String fullName, required String phoneNumber, required String password, required String otp}) async {
    final response = await _api.request<Map<String, dynamic>>('/auth/register', method: 'POST', authenticated: false, data: {
      'fullName': fullName.trim(),
      'otp': otp.trim(),
      'phoneNumber': phoneNumber.trim(),
      'password': password,
      'deviceName': 'Flutter',
    });
    return AuthSession.fromJson(response.data!);
  }

  Future<void> requestOtp(String phoneNumber, {required bool reset}) async {
    await _api.request<Map<String, dynamic>>(
      reset ? '/auth/request-password-reset-otp' : '/auth/request-register-otp',
      method: 'POST', authenticated: false, data: {'phoneNumber': phoneNumber.trim()},
    );
  }

  Future<void> resetPassword(String phoneNumber, String otp, String newPassword) async {
    await _api.request<Map<String, dynamic>>(
      '/auth/reset-password', method: 'POST', authenticated: false,
      data: {'phoneNumber': phoneNumber.trim(), 'otp': otp.trim(), 'newPassword': newPassword},
    );
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _api.request<Map<String, dynamic>>(
      '/auth/change-password', method: 'POST',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Future<User> me() async {
    final response = await _api.request<Map<String, dynamic>>('/users/me');
    return User.fromJson(response.data!);
  }

  Future<void> logout(String refreshToken) async {
    try {
      await _api.request<void>('/auth/logout', method: 'POST', data: {'refreshToken': refreshToken});
    } catch (_) {
      // Local logout must still complete if server is unavailable.
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider)));
