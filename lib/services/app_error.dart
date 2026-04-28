import 'package:dio/dio.dart';

enum AppErrorType { network, auth, validation, server, unknown }

class AppError implements Exception {
  final AppErrorType type;
  final String message;
  final int? statusCode;
  // Canonical machine-readable code from the backend payload. Lets
  // screens route on "premium_feature_locked" / "premium_expired" /
  // "branch_not_owned" without string-matching against Spanish copy.
  final String? errorCode;
  // Raw server payload (decoded JSON object). Optional; only set when
  // the response carries structured data the caller needs to inspect
  // — e.g. a 409 cart_locked includes "holder" with the rival
  // employee's display info so the snackbar can name them.
  final Map<String, dynamic>? payload;

  const AppError({
    required this.type,
    required this.message,
    this.statusCode,
    this.errorCode,
    this.payload,
  });

  /// Convenience predicate used by views that want to short-circuit
  /// their own UX when the backend blocked the call with a premium
  /// paywall. Matches either error_code (legacy "premium_expired")
  /// or the canonical "premium_feature_locked" tag.
  bool get isPremiumLocked {
    if (statusCode != 403) return false;
    return errorCode == 'premium_expired' ||
        errorCode == 'premium_feature_locked';
  }

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
    final rawCode = _pickErrorCode(data);

    if (statusCode == 401) {
      return const AppError(
        type: AppErrorType.auth,
        message: 'Tu sesión expiró. Por favor inicia sesión de nuevo.',
        statusCode: 401,
      );
    }

    if (statusCode == 403) {
      // Premium paywall branch: surface the backend's human-readable
      // message (when present) + the structured code so views can
      // route on it. Falls back to a neutral "sin acceso" copy.
      final serverMsg = data is Map
          ? (data['message'] as String? ?? data['error'] as String?)
          : null;
      return AppError(
        type: AppErrorType.auth,
        message: serverMsg ?? 'No tienes acceso a esta función.',
        statusCode: 403,
        errorCode: rawCode,
      );
    }

    if (statusCode == 422 || statusCode == 400) {
      final serverMsg = data is Map ? data['error'] as String? : null;
      return AppError(
        type: AppErrorType.validation,
        message: serverMsg ?? 'Revisa los campos marcados.',
        statusCode: statusCode,
        errorCode: rawCode,
      );
    }

    if (statusCode == 409) {
      final serverMsg = data is Map ? data['error'] as String? : null;
      return AppError(
        type: AppErrorType.validation,
        message: serverMsg ?? 'Ese registro ya existe.',
        statusCode: 409,
        errorCode: rawCode,
        payload: data is Map<String, dynamic> ? data : null,
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
        errorCode: rawCode,
      );
    }

    return AppError(
      type: AppErrorType.unknown,
      message: 'Algo salió mal. Intente de nuevo.',
      statusCode: statusCode,
      errorCode: rawCode,
    );
  }

  /// Extract the first machine-readable code present in the server
  /// payload. New callers should prefer the canonical `error` field
  /// (2026-04-24 shape ships "premium_feature_locked" there); we fall
  /// back to the legacy `error_code` when the new key is absent or
  /// doesn't look like a code (heuristic: lowercase + underscore).
  static String? _pickErrorCode(Object? data) {
    if (data is! Map) return null;
    final err = data['error'];
    if (err is String && err.isNotEmpty && !err.contains(' ')) {
      return err;
    }
    final legacy = data['error_code'];
    if (legacy is String && legacy.isNotEmpty) return legacy;
    return null;
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
