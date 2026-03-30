import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  ApiConfig._();

  /// Compile-time override (--dart-define=API_BASE_URL=...)
  static const _envUrl = String.fromEnvironment('API_BASE_URL');

  /// Resolved base URL for all API calls.
  /// Priority: compile-time > .env > fallback per platform.
  static String get baseUrl {
    if (_envUrl.isNotEmpty) return _envUrl;

    final dotenvUrl = dotenv.maybeGet('API_BASE_URL');
    if (dotenvUrl != null && dotenvUrl.isNotEmpty) return dotenvUrl;

    // Fallback: producción en Render
    return 'https://vendia-api.onrender.com';
  }
}
