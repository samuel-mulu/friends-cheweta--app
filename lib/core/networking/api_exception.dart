import 'package:dio/dio.dart';
import 'package:friends_game_app/core/errors/app_failure.dart';

AppFailure mapDioException(DioException error) {
  final response = error.response;
  final data = response?.data;
  final code = data is Map<String, dynamic> ? data['code']?.toString() : null;
  final serverMessage = data is Map<String, dynamic> ? data['message']?.toString() : null;

  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout) {
    return const AppFailure(
      kind: FailureKind.network,
      message: 'Unable to reach the server. Check your connection and try again.',
    );
  }

  switch (response?.statusCode) {
    case 400:
      return AppFailure(kind: FailureKind.validation, code: code, message: serverMessage ?? 'Please check the information and try again.');
    case 401:
      return AppFailure(kind: FailureKind.unauthorized, code: code, message: serverMessage ?? 'Your session has expired.');
    case 403:
      return AppFailure(kind: FailureKind.forbidden, code: code, message: code == 'ACCOUNT_BLOCKED' ? 'Your account is currently unavailable. Please contact support.' : (serverMessage ?? 'You are not allowed to perform this action.'));
    case 409:
      return AppFailure(kind: FailureKind.business, code: code, message: serverMessage ?? 'This action conflicts with the current state.');
    default:
      if (response != null && response.statusCode != null && response.statusCode! >= 500) {
        return const AppFailure(kind: FailureKind.server, message: 'The service is temporarily unavailable. Please try again.');
      }
      return AppFailure(kind: FailureKind.unknown, code: code, message: serverMessage ?? 'Something went wrong. Please try again.');
  }
}
