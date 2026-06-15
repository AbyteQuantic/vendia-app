// Pruebas de integración sobre Isar REAL (no mock). Esta capa es la que faltaba:
// los ~1471 tests unitarios mockean la DB, así que la serialización real en
// `put()` —donde vivía el LateInitializationError de `reservedStock`— nunca se
// ejercitaba. Estos tests abren un Isar real (DatabaseService.initForTest) y
// verifican que las escrituras críticas persisten de verdad.
//
// Correr:  flutter test integration_test/isar_persistence_test.dart
// En CI corren headless (Isar.initializeIsarCore baja el core nativo).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/database/database_service.dart';
import 'package:vendia_pos/database/collections/local_product.dart';
import 'package:vendia_pos/database/collections/local_sale.dart';
import 'package:vendia_pos/database/collections/local_credit.dart';
import 'package:vendia_pos/database/collections/local_customer.dart';
import 'package:vendia_pos/database/local_product_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('isar_it');
    await DatabaseService.initForTest(
      directory: tmp.path,
      name: 'it_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    await DatabaseService.closeForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  final db = DatabaseService.instance;

  group('Producto — serialización real (la clase del bug reservedStock)', () {
    test('crear producto vía factory persiste TODOS los campos', () async {
      final p = buildSavedLocalProduct(
        uuid: 'p-1',
        name: 'Arroz',
        price: 4200,
        stock: 10,
        imageUrl: 'https://r2/arroz.png',
        barcode: '7702',
        presentation: 'bolsa',
        content: '500g',
      );
      await db.upsertProduct(p); // el bug viejo: put() lanzaba aquí offline

      final got = await db.getProductByUuid('p-1');
      expect(got, isNotNull);
      expect(got!.name, 'Arroz');
      expect(got.price, 4200);
      expect(got.stock, 10);
      expect(got.reservedStock, 0); // el campo late que faltaba
      expect(got.barcode, '7702');
      expect(got.presentation, 'bolsa');
    });

    test(
        'CONTROL NEGATIVO: construir LocalProduct SIN reservedStock revienta el '
        'put() (prueba que el trap es real y la factory es obligatoria)',
        () async {
      final raw = LocalProduct()
        ..uuid = 'p-raw'
        ..name = 'X'
        ..price = 1000
        ..stock = 5
        // ..reservedStock = 0   ← OMITIDO a propósito
        ..isAvailable = true
        ..requiresContainer = false
        ..containerPrice = 0
        ..clientUpdatedAt = DateTime(2026);
      // La serialización Isar lee reservedStock (late sin set) → lanza.
      await expectLater(() => db.upsertProduct(raw), throwsA(anything));
    });

    test('editar el mismo uuid no duplica filas (upsert real)', () async {
      await db.upsertProduct(buildSavedLocalProduct(
          uuid: 'p-2', name: 'V1', price: 100, stock: 1));
      await db.upsertProduct(buildSavedLocalProduct(
          uuid: 'p-2', name: 'V2', price: 200, stock: 9));
      final all = await db.getAllProducts();
      final mine = all.where((p) => p.uuid == 'p-2').toList();
      expect(mine.length, 1);
      expect(mine.first.price, 200);
      expect(mine.first.stock, 9);
    });
  });

  group('Venta — atómica con descuento de stock (Isar real)', () {
    test('insertSaleAndDeductStock guarda la venta y descuenta stock', () async {
      await db.upsertProduct(buildSavedLocalProduct(
          uuid: 'sku-1', name: 'Gaseosa', price: 2000, stock: 10));

      final sale = LocalSale()
        ..uuid = 'a1b2c3d4-0000-4000-8000-000000000001'
        ..total = 6000
        ..paymentMethod = 'cash'
        ..employeeName = 'Caja 1'
        ..isCreditSale = false
        ..saleOrigin = 'counter'
        ..items = [
          SaleItemEmbed()
            ..productUuid = 'sku-1'
            ..productName = 'Gaseosa'
            ..quantity = 3
            ..unitPrice = 2000
            ..isContainerCharge = false
        ]
        ..createdAt = DateTime(2026)
        ..synced = false;

      await db.insertSaleAndDeductStock(sale);

      final prod = await db.getProductByUuid('sku-1');
      expect(prod!.stock, 7, reason: '10 - 3, descontado en la misma txn');

      final unsynced = await db.getUnsyncedSales();
      expect(unsynced.any((s) => s.uuid == sale.uuid), isTrue);
      expect(unsynced.first.items.first.unitPrice, 2000);
    });
  });

  group('Fiado — lista embebida late (payments)', () {
    test('crédito con payments=[] persiste sin reventar', () async {
      final c = LocalCustomer()
        ..uuid = 'c-1'
        ..name = 'Doña Rosa'
        ..phone = '300'
        ..email = ''
        ..totalCredit = 5000
        ..totalPaid = 0
        ..createdAt = DateTime(2026)
        ..clientUpdatedAt = DateTime(2026);
      await db.upsertCustomer(c);

      final credit = LocalCredit()
        ..uuid = 'cr-1'
        ..customerUuid = 'c-1'
        ..saleUuid = ''
        ..totalAmount = 5000
        ..paidAmount = 0
        ..status = 'pending'
        ..payments = [] // late List — debe round-trippear como []
        ..createdAt = DateTime(2026)
        ..clientUpdatedAt = DateTime(2026);
      await db.upsertCredit(credit);

      final got = await db.getCreditByUuid('cr-1');
      expect(got, isNotNull);
      expect(got!.payments, isEmpty);
      expect(got.totalAmount, 5000);
    });
  });

  group('Merge de catálogo (H1) — sobre Isar real', () {
    test('replaceAllProducts preserva reservedStock local', () async {
      // Producto local con una reserva de mesa.
      final local = buildSavedLocalProduct(
          uuid: 'm-1', name: 'Cerveza', price: 3000, stock: 24)
        ..reservedStock = 4;
      await db.upsertProduct(local);

      // El servidor lo manda con reserved_stock 0 (no lo conoce).
      final fromServer = LocalProduct.fromJson(const {
        'id': 'm-1',
        'name': 'Cerveza',
        'price': 3200,
        'stock': 24,
        'reserved_stock': 0,
      });
      await db.replaceAllProducts([fromServer]);

      final got = await db.getProductByUuid('m-1');
      expect(got!.price, 3200, reason: 'precio del server gana');
      expect(got.reservedStock, 4, reason: 'la reserva local NO se pierde');
      expect(got.availableStock, 20);
    });
  });
}
