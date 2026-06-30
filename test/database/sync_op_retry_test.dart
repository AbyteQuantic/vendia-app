// Spec: specs/047-offline-sync-contract/spec.md
//
// Bug histórico (lote envenenado) reproducido para fiado/crédito: la cola
// genérica de /sync/batch mandaba TODOS los pending ops en un solo POST; un
// único op con payload inválido hacía fallar la transacción del backend
// entera (ProcessBatch envuelve todo el lote en una sola db.Transaction) y
// el código viejo dejaba a TODOS los ops de ese lote (hasta 50) sin
// sincronizar para siempre, porque el op envenenado nunca se quitaba de
// getPendingOps(). El fix manda cada op en su propio POST; shouldDropSyncOp
// decide cuándo un op individual se descarta (en vez de quedar congelado
// re-enviándose para siempre) — a diferencia de isPermanentSalePushError
// (sales_sync.dart), que puede confiar en 400/422 porque /sales es un
// endpoint dedicado, /sync/batch devuelve 500 genérico para CUALQUIER
// fallo de processOperation, así que la señal es retryCount.
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/database/sync/sync_service.dart';

void main() {
  group('shouldDropSyncOp', () {
    test('op fresco (retryCount=0) NO se descarta — se reintenta', () {
      expect(shouldDropSyncOp(0), isFalse);
    });

    test('justo debajo del tope sigue reintentándose', () {
      expect(shouldDropSyncOp(maxSyncOpRetries - 1), isFalse);
    });

    test('al llegar al tope de reintentos SE DESCARTA', () {
      expect(shouldDropSyncOp(maxSyncOpRetries), isTrue);
    });

    test('por encima del tope sigue descartándose (no se congela)', () {
      expect(shouldDropSyncOp(maxSyncOpRetries + 5), isTrue);
    });
  });
}
