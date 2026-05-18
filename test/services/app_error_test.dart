// Spec: specs/007-web-logo-upload/spec.md (AC-03/AC-04)
// Spec: specs/012-cold-start-resiliencia/spec.md (FR-04/AC-02)
//
// Covers AppError.fromDioException — the layer the logo step (and
// every screen) relies on to surface a real cause instead of a
// generic "intente más tarde".
//
// Spec 012 changed the connectionError branch: that error is now only
// reached after the cold-start retry interceptor has exhausted its
// attempts, so the copy is a single soft, non-alarming message
// ("No pudimos conectar...") that fits both a genuinely unreachable
// backend and a real no-internet case, on every platform.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/app_error.dart';

DioException _dio({
  DioExceptionType type = DioExceptionType.badResponse,
  int? status,
  Object? data,
}) {
  final req = RequestOptions(path: '/api/v1/auth/preview-logo');
  return DioException(
    requestOptions: req,
    type: type,
    response: status == null
        ? null
        : Response(requestOptions: req, statusCode: status, data: data),
  );
}

void main() {
  group('AppError.fromDioException', () {
    test('timeout types map to a network error with the slow-connection copy',
        () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        final err = AppError.fromDioException(_dio(type: t));
        expect(err.type, AppErrorType.network);
        expect(err.message, contains('tardó'));
      }
    });

    test(
        'connectionError maps to a network error with the soft '
        'cold-start copy (Spec 012 FR-04)', () {
      final err = AppError.fromDioException(
        _dio(type: DioExceptionType.connectionError),
      );
      expect(err.type, AppErrorType.network);
      // Reached only after the retry interceptor gave up — soft, not
      // alarming, and fits the real no-internet case too.
      expect(err.message,
          'No pudimos conectar. Revisa tu internet e intenta de nuevo.');
    });

    test('a 500 surfaces the backend "error" field — not a generic toast', () {
      final err = AppError.fromDioException(_dio(
        status: 500,
        data: {'error': 'error al generar logo: gemini API returned 429'},
      ));
      expect(err.type, AppErrorType.server);
      expect(err.statusCode, 500);
      expect(err.message, contains('error al generar logo'));
      expect(err.message, contains('429'));
    });

    test('a 500 with both error and detail concatenates them', () {
      final err = AppError.fromDioException(_dio(
        status: 500,
        data: {'error': 'Error del servidor', 'detail': 'almacenamiento caído'},
      ));
      expect(err.message, contains('Error del servidor'));
      expect(err.message, contains('almacenamiento caído'));
    });

    test('a 500 with no payload falls back to the generic server copy', () {
      final err = AppError.fromDioException(_dio(status: 500));
      expect(err.type, AppErrorType.server);
      expect(err.message, 'Error del servidor. Intenta de nuevo.');
    });

    test('a 400 surfaces the backend validation message', () {
      final err = AppError.fromDioException(_dio(
        status: 400,
        data: {
          'error': 'describa su negocio (mínimo 12 caracteres)',
          'error_code': 'logo_details_required',
        },
      ));
      expect(err.type, AppErrorType.validation);
      expect(err.message, contains('mínimo 12 caracteres'));
      expect(err.errorCode, 'logo_details_required');
    });

    test('a 401 maps to an auth error with the session-expired copy', () {
      final err = AppError.fromDioException(_dio(status: 401));
      expect(err.type, AppErrorType.auth);
      expect(err.message, contains('sesión'));
    });
  });
}
