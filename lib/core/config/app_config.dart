import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.socketBaseUrl,
  });

  final String environment;
  final String apiBaseUrl;
  final String socketBaseUrl;

  static const String _apiBaseUrlEnv = String.fromEnvironment('API_BASE_URL');
  static const String _socketBaseUrlEnv = String.fromEnvironment('SOCKET_BASE_URL');

  /// Active config for this run: `--dart-define` overrides, else local dev defaults.
  static AppConfig get current {
    final envApiBaseUrl = dotenv.maybeGet('API_BASE_URL') ?? '';
    final envSocketBaseUrl = dotenv.maybeGet('SOCKET_BASE_URL') ?? '';
    // Trailing slashes are dropped: paths are appended as '/game', '/auth/…', so
    // "https://host//" would otherwise become "https://host///game" (a socket
    // namespace that does not exist: the app never connects).
    final apiBaseUrl = _trimSlashes(_apiBaseUrlEnv.isNotEmpty ? _apiBaseUrlEnv : envApiBaseUrl);
    final socketBaseUrl = _trimSlashes(_socketBaseUrlEnv.isNotEmpty ? _socketBaseUrlEnv : envSocketBaseUrl);

    if (apiBaseUrl.isNotEmpty && socketBaseUrl.isNotEmpty) {
      return AppConfig(
        environment: kReleaseMode ? 'production' : 'development',
        apiBaseUrl: apiBaseUrl,
        socketBaseUrl: socketBaseUrl,
      );
    }

    final host = _localDevHost();
    return AppConfig(
      environment: 'development',
      apiBaseUrl: 'http://$host:5000/api',
      socketBaseUrl: 'http://$host:5000',
    );
  }

  static String _trimSlashes(String url) => url.trim().replaceFirst(RegExp(r'/+$'), '');

  static String _localDevHost() {
    if (kIsWeb) return '127.0.0.1';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return '10.0.2.2';
      default:
        return 'localhost';
    }
  }
}
