// Spec: specs/047-offline-sync-contract/spec.md — pase de ESTRÉS / property.
//
// Ejercita las funciones puras del hardening a escala y sobre miles de entradas
// aleatorias (seed fijo → reproducible) verificando que las INVARIANTES se
// mantienen siempre. Si alguna combinación rompe una invariante, falla aquí.

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/money_split.dart';
import 'package:vendia_pos/database/collections/local_product.dart';
import 'package:vendia_pos/database/collections/local_credit.dart';
import 'package:vendia_pos/database/sync/product_merge.dart';
import 'package:vendia_pos/database/sync/sync_payloads.dart';

LocalProduct prod(String uuid, {int stock = 10, int reserved = 0}) =>
    LocalProduct()
      ..uuid = uuid
      ..name = 'P-$uuid'
      ..price = 1000
      ..stock = stock
      ..reservedStock = reserved
      ..isAvailable = true
      ..requiresContainer = false
      ..containerPrice = 0
      ..clientUpdatedAt = DateTime(2026);

void main() {
  test('evenSplitCOP/representativeSplitCOP: 50.000 combinaciones aleatorias '
      'mantienen las invariantes', () {
    final rnd = Random(20260614);
    for (var i = 0; i < 50000; i++) {
      final total = rnd.nextInt(10000000); // 0 .. 10M COP
      final count = 1 + rnd.nextInt(50); // 1 .. 50 personas

      final shares = evenSplitCOP(total, count);
      expect(shares.length, count);
      final sum = shares.fold<int>(0, (a, b) => a + b);

      if (count == 1) {
        // 1 persona paga el total EXACTO (lo que debe, sin redondear).
        expect(shares.single, total, reason: 'total=$total count=1');
        continue;
      }

      // 1) Las partes suman exactamente el total redondeado a $50 (sin sobrante).
      expect(sum, roundToCopStep(total), reason: 'total=$total count=$count');
      // 2) Cada parte es múltiplo de $50.
      for (final s in shares) {
        expect(s % 50, 0, reason: 'total=$total count=$count parte=$s');
      }
      // 3) Las partes difieren a lo sumo un escalón de $50.
      final maxS = shares.reduce(max);
      final minS = shares.reduce(min);
      expect(maxS - minS, lessThanOrEqualTo(50),
          reason: 'total=$total count=$count');
      // 4) El monto representativo NUNCA hace que el grupo pague de más.
      final rep = representativeSplitCOP(total, count);
      expect(rep * count, lessThanOrEqualTo(total + 50),
          reason: 'total=$total count=$count rep=$rep');
    }
  });

  test('mergeServerProducts: 10.000 productos preservan reservas, protegen '
      'offline y eliminan borrados — sin duplicados ni pérdidas', () {
    const n = 10000;
    final existing = <LocalProduct>[];
    for (var i = 0; i < n; i++) {
      existing.add(prod('p-$i', stock: 100, reserved: i % 7));
    }
    // 200 productos creados offline (no vienen del servidor).
    final protected = <String>{};
    for (var i = 0; i < 200; i++) {
      final uuid = 'offline-$i';
      existing.add(prod(uuid));
      protected.add(uuid);
    }

    // El servidor manda los mismos n productos (reserved=0) + 500 nuevos,
    // y "borró" los primeros 1000 (no los manda).
    final incoming = <LocalProduct>[];
    for (var i = 1000; i < n; i++) {
      incoming.add(prod('p-$i', stock: 100, reserved: 0));
    }
    for (var i = 0; i < 500; i++) {
      incoming.add(prod('new-$i', stock: 5, reserved: 0));
    }

    final sw = Stopwatch()..start();
    final merged = mergeServerProducts(
      existing: existing,
      incoming: incoming,
      protectedUuids: protected,
    );
    sw.stop();

    final byUuid = {for (final p in merged) p.uuid: p};
    // Sin duplicados.
    expect(byUuid.length, merged.length);
    // Los borrados (p-0..p-999) NO protegidos desaparecieron.
    expect(byUuid.containsKey('p-0'), isFalse);
    expect(byUuid.containsKey('p-999'), isFalse);
    // Los que siguen en el server conservan su reserva local.
    expect(byUuid['p-1000']!.reservedStock, 1000 % 7);
    expect(byUuid['p-5000']!.reservedStock, 5000 % 7);
    // Los nuevos del server entraron.
    expect(byUuid.containsKey('new-0'), isTrue);
    // Los offline protegidos sobrevivieron aunque el server no los conoce.
    expect(byUuid.containsKey('offline-0'), isTrue);
    expect(byUuid.containsKey('offline-199'), isTrue);
    // Conteo total: (10000-1000) server + 500 nuevos + 200 offline.
    expect(merged.length, 9000 + 500 + 200);
    // Rendimiento razonable a escala (no O(n^2)).
    expect(sw.elapsedMilliseconds, lessThan(2000),
        reason: 'merge de ~10k tomó ${sw.elapsedMilliseconds}ms');
  });

  test('creditAccountSyncPayload: 20.000 créditos aleatorios siempre emiten '
      'montos enteros, columnas válidas y omiten sale_id vacío', () {
    final rnd = Random(7);
    for (var i = 0; i < 20000; i++) {
      final total = rnd.nextDouble() * 5000000;
      final paid = rnd.nextDouble() * total;
      final hasSale = rnd.nextBool();
      final c = LocalCredit()
        ..uuid = 'cr-$i'
        ..customerUuid = 'c-$i'
        ..saleUuid = hasSale ? 's-$i' : ''
        ..totalAmount = total
        ..paidAmount = paid
        ..status = 'pending'
        ..payments = []
        ..createdAt = DateTime(2026)
        ..clientUpdatedAt = DateTime(2026);

      final p = creditAccountSyncPayload(c);
      // Montos enteros (columnas int64) — nunca double.
      expect(p['total_amount'], isA<int>());
      expect(p['paid_amount'], isA<int>());
      expect(p['total_amount'], total.round());
      // Nunca llaves que no son columnas.
      expect(p.containsKey('uuid'), isFalse);
      expect(p.containsKey('payments'), isFalse);
      expect(p.containsKey('customer_uuid'), isFalse);
      // sale_id presente sii hay venta (nunca "" en columna uuid).
      expect(p.containsKey('sale_id'), hasSale);
    }
  });
}
