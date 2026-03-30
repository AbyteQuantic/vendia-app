import 'package:dio/dio.dart';
import '../../config/api_config.dart';

/// Cliente HTTP base para VendIA.
/// Lee [API_BASE_URL] desde el .env vía [ApiConfig].
class ApiClient {
  static ApiClient? _instance;
  late final Dio dio;

  ApiClient._() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  factory ApiClient() => _instance ??= ApiClient._();

  /// Hace un health check al backend.
  Future<String> healthCheck() async {
    final response = await dio.get('/ping');
    return response.data.toString();
  }
}
