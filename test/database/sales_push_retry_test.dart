// Spec: specs/047-offline-sync-contract/spec.md
//
// Una venta offline que el servidor rechaza por contrato (400/422) NO debe
// reintentarse cada 30 s para siempre; un fallo transitorio (5xx, red, timeout,
// 401/403) SÍ debe reintentarse. Este clasificador decide cuál es cuál — el
// bucle de reintento infinito que señaló el concilio se cierra aquí.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/sync/sales_sync.dart';
import 'package:vendia_pos/services/app_error.dart';

void main() {
  group('isPermanentSalePushError', () {
    test('400 (bad request) es PERMANENTE → se drena, no se reintenta', () {
      expect(
          isPermanentSalePushError(const AppError(
              type: AppErrorType.validation,
              message: 'inválido',
              statusCode: 400)),
          isTrue);
    });

    test('422 (unprocessable) es PERMANENTE', () {
      expect(
          isPermanentSalePushError(const AppError(
              type: AppErrorType.validation,
              message: 'no procesable',
              statusCode: 422)),
          isTrue);
    });

    test('500 (server) es TRANSITORIO → se reintenta', () {
      expect(
          isPermanentSalePushError(const AppError(
              type: AppErrorType.server, message: 'server', statusCode: 500)),
          isFalse);
    });

    test('401/403 (token) es TRANSITORIO → se reintenta tras refrescar', () {
      expect(
          isPermanentSalePushError(const AppError(
              type: AppErrorType.auth, message: 'auth', statusCode: 401)),
          isFalse);
      expect(
          isPermanentSalePushError(const AppError(
              type: AppErrorType.auth, message: 'forbidden', statusCode: 403)),
          isFalse);
    });

    test('error sin statusCode (red caída/timeout) es TRANSITORIO', () {
      expect(
          isPermanentSalePushError(
              const AppError(type: AppErrorType.network, message: 'sin red')),
          isFalse);
      expect(isPermanentSalePushError(Exception('socket')), isFalse);
    });
  });
}
