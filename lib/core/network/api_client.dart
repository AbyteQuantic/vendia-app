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
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ));
  }

  factory ApiClient() => _instance ??= ApiClient._();

  /// Hace un health check al backend (/ping está fuera de /api/v1).
  /// Retorna el body de respuesta si es exitoso, o lanza excepción.
  Future<String> healthCheck() async {
    // /ping es relativo a la raíz del servidor, no al baseUrl (/api/v1)
    final baseUri = Uri.parse(ApiConfig.baseUrl);
    final pingUrl = '${baseUri.scheme}://${baseUri.host}:${baseUri.port}/ping';
    final response = await dio.get(pingUrl);
    return response.data.toString();
  }
}
