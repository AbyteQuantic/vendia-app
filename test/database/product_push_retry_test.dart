// Spec: specs/047-offline-sync-contract/spec.md
//
// Bug real: un producto creado SIN internet se guardaba local + se marcaba
// pendiente (PendingProductPush.add), pero nada volvía a intentar subirlo —
// remove() nunca se llamaba desde ningún lado salvo el test. El producto
// quedaba protegido de borrarse localmente para siempre, pero JAMÁS llegaba
// al servidor: invisible en otras sedes/reportes, y perdido si el celular se
// pierde o se reinstala antes de recuperar señal. Este archivo cubre el
// clasificador de errores y el payload — la parte pura y testeable sin Isar.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/collections/local_product.dart';
import 'package:vendia_pos/database/sync/product_push_sync.dart';
import 'package:vendia_pos/services/app_error.dart';

LocalProduct _p({
  String uuid = 'a1b2c3d4-0000-4000-8000-000000000000',
  String name = 'Arroz',
  double price = 4200,
  int stock = 10,
  int minStock = 0,
  String? barcode,
  String? presentation,
  String? category,
  DateTime? expiryDate,
}) {
  return LocalProduct()
    ..uuid = uuid
    ..name = name
    ..price = price
    ..stock = stock
    ..reservedStock = 0
    ..minStock = minStock
    ..isAvailable = true
    ..requiresContainer = false
    ..containerPrice = 0
    ..barcode = barcode
    ..presentation = presentation
    ..content = ''
    ..category = category
    ..characteristics = null
    ..expiryDate = expiryDate
    ..clientUpdatedAt = DateTime(2026, 1, 1);
}

void main() {
  group('productSyncPayload', () {
    test('mapea id (no uuid) + campos aceptados por CreateProduct', () {
      final p = productSyncPayload(_p(barcode: '7501', presentation: 'Bolsa', category: 'Abarrotes'));
      expect(p['id'], 'a1b2c3d4-0000-4000-8000-000000000000');
      expect(p.containsKey('uuid'), isFalse); // el backend espera "id"
      expect(p['name'], 'Arroz');
      expect(p['price'], 4200);
      expect(p['stock'], 10);
      expect(p['barcode'], '7501');
      expect(p['presentation'], 'Bolsa');
      expect(p['category'], 'Abarrotes');
    });

    test('expiry_date se serializa YYYY-MM-DD cuando existe', () {
      final p = productSyncPayload(_p(expiryDate: DateTime(2026, 3, 5)));
      expect(p['expiry_date'], '2026-03-05');
    });

    test('sin fecha de vencimiento, no manda expiry_date', () {
      final p = productSyncPayload(_p());
      expect(p.containsKey('expiry_date'), isFalse);
    });
  });

  group('isPermanentProductPushError', () {
    test('duplicate_product es PERMANENTE (otro producto ya tiene ese nombre) → se drena', () {
      expect(
          isPermanentProductPushError(const AppError(
              type: AppErrorType.validation,
              message: 'ya existe',
              statusCode: 409,
              errorCode: 'duplicate_product')),
          isTrue);
    });

    test('400/422 son PERMANENTES', () {
      expect(
          isPermanentProductPushError(const AppError(
              type: AppErrorType.validation, message: 'x', statusCode: 400)),
          isTrue);
      expect(
          isPermanentProductPushError(const AppError(
              type: AppErrorType.validation, message: 'x', statusCode: 422)),
          isTrue);
    });

    test('500/red/timeout son TRANSITORIOS → se reintentan', () {
      expect(
          isPermanentProductPushError(const AppError(
              type: AppErrorType.server, message: 'x', statusCode: 500)),
          isFalse);
      expect(
          isPermanentProductPushError(
              const AppError(type: AppErrorType.network, message: 'sin red')),
          isFalse);
      expect(isPermanentProductPushError(Exception('socket')), isFalse);
    });
  });
}
