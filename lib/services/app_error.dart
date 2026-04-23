import 'package:dio/dio.dart';

enum AppErrorType { network, auth, validation, server, unknown }

class AppError implements Exception {
  final AppErrorType type;
  final String message;
  final int? statusCode;

  const AppError({
    required this.type,
    required this.message,
    this.statusCode,
  });

  factory AppError.fromDioException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const AppError(
        type: AppErrorType.network,
        message: 'La conexión tardó demasiado. Intente de nuevo.',
      );
    }

    if (e.type == DioExceptionType.connectionError) {
      return const AppError(
        type: AppErrorType.network,
        message: 'Sin conexión a internet. Verifique su red.',
      );
    }

    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    if (statusCode == 401) {
      return const AppError(
        type: AppErrorType.auth,
        message: 'Tu sesión expiró. Por favor inicia sesión de nuevo.',
        statusCode: 401,
      );
    }

    if (statusCode == 422 || statusCode == 400) {
      final serverMsg = data is Map ? data['error'] as String? : null;
      return AppError(
        type: AppErrorType.validation,
        message: serverMsg ?? 'Revisa los campos marcados.',
        statusCode: statusCode,
      );
    }

    if (statusCode == 409) {
      final serverMsg = data is Map ? data['error'] as String? : null;
      return AppError(
        type: AppErrorType.validation,
        message: serverMsg ?? 'Ese registro ya existe.',
        statusCode: 409,
      );
    }

    if (statusCode != null && statusCode >= 500) {
      final serverMsg = data is Map ? data['error'] as String? : null;
      // When the backend includes a "detail" field (e.g. pass-through
      // of the raw DB/driver error from promotions or admin_catalogs),
      // append it so the user sees something actionable instead of the
      // generic 500 toast. We truncate to keep a single-line snackbar.
      final rawDetail = data is Map ? data['detail'] as String? : null;
      final detail = rawDetail != null && rawDetail.isNotEmpty
          ? (rawDetail.length > 180
              ? '${rawDetail.substring(0, 180)}…'
              : rawDetail)
          : null;
      final combined = detail == null
          ? (serverMsg ?? 'Error del servidor. Intenta de nuevo.')
          : '${serverMsg ?? 'Error del servidor'} — $detail';
      return AppError(
        type: AppErrorType.server,
        message: combined,
        statusCode: statusCode,
      );
    }

    return const AppError(
      type: AppErrorType.unknown,
      message: 'Algo salió mal. Intente de nuevo.',
    );
  }

  factory AppError.fromException(Object e) {
    if (e is DioException) return AppError.fromDioException(e);
    if (e is AppError) return e;
    final msg = e.toString();
    if (msg.contains('SocketException') || msg.contains('connection')) {
      return const AppError(
        type: AppErrorType.network,
        message: 'Sin conexión a internet. Verifique su red.',
      );
    }
    return const AppError(
      type: AppErrorType.unknown,
      message: 'Algo salió mal. Intente de nuevo.',
    );
  }

  @override
  String toString() => 'AppError($type): $message';
}
