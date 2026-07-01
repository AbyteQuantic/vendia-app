// Spec: specs/047-offline-sync-contract/spec.md
//
// Bug histórico (doble push): el push inmediato fire-and-forget del screen
// (_syncSaleToBackend en pos_screen.dart) y el sweep periódico de
// SalesSyncService.pushToServer llamaban a api.createSale para el MISMO
// uuid de forma totalmente independiente, confiando ciegamente en que el
// backend fuera idempotente por UUID. En una red lenta el timer de 30 s
// podía disparar justo cuando el push inmediato seguía en vuelo y la misma
// venta salía POSTeada casi simultáneamente por los dos caminos.
// acquireSalePush/releaseSalePush son el guard compartido que serializa
// ambos caminos para un mismo uuid — este test reproduce la condición de
// carrera en aislamiento (sin Isar/Dio reales), igual que el resto de la
// suite en este directorio.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/sync/sales_sync.dart';

void main() {
  setUp(resetSalesPushInFlightForTest);
  tearDown(resetSalesPushInFlightForTest);

  group('acquireSalePush / releaseSalePush', () {
    test('primera reserva de un uuid libre SIEMPRE se concede', () {
      expect(acquireSalePush('venta-1'), isTrue);
    });

    test(
        'reserva concurrente del MISMO uuid (carrera screen vs sweep) se '
        'RECHAZA — esto es lo que evita el doble POST', () {
      expect(acquireSalePush('venta-1'), isTrue);
      // Segundo camino (el sweep de 30 s, o viceversa) intenta el MISMO
      // uuid mientras el primero sigue en vuelo: debe rechazarse para que
      // solo UN camino llame a api.createSale.
      expect(acquireSalePush('venta-1'), isFalse);
    });

    test('uuids distintos no se bloquean entre sí', () {
      expect(acquireSalePush('venta-1'), isTrue);
      expect(acquireSalePush('venta-2'), isTrue);
    });

    test('tras liberar, el mismo uuid puede reservarse de nuevo (el dueño '
        'anterior ya terminó — éxito o fallo transitorio)', () {
      expect(acquireSalePush('venta-1'), isTrue);
      releaseSalePush('venta-1');
      expect(acquireSalePush('venta-1'), isTrue);
    });

    test('liberar un uuid que nunca se reservó no rompe nada (finally '
        'defensivo)', () {
      expect(() => releaseSalePush('nunca-reservado'), returnsNormally);
    });
  });
}
