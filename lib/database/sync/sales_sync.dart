import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../database_service.dart';
import '../collections/local_sale.dart';

/// Bidirectional sales sync:
/// 1. Pull: downloads sales from server → Isar (on app start)
/// 2. Push: uploads unsynced local sales → server (after each sale)
class SalesSyncService {
  static Future<void> pullFromServer() async {
    try {
      final api = ApiService(AuthService());
      // Fetch last 100 sales from server
      final res = await api.fetchSales(page: 1, perPage: 100);
      final serverSales = (res['data'] as List?) ?? [];

      if (serverSales.isEmpty) return;

      final db = DatabaseService.instance;

      // Get existing local UUIDs to avoid duplicates
      final localSales = await db.getRecentSales(limit: 500);
      final localUuids = localSales.map((s) => s.uuid).toSet();

      final newSales = <LocalSale>[];
      for (final s in serverSales) {
        final sale = s as Map<String, dynamic>;
        final id = sale['id'] as String? ?? '';
        if (id.isEmpty || localUuids.contains(id)) continue;

        final items = (sale['items'] as List? ?? []).map((item) {
          final i = item as Map<String, dynamic>;
          return SaleItemEmbed()
            ..productUuid = i['product_id'] as String? ?? ''
            ..productName = i['name'] as String? ?? ''
            ..quantity = i['quantity'] as int? ?? 1
            ..unitPrice = (i['price'] as num?)?.toDouble() ?? 0
            ..isContainerCharge = i['is_container_charge'] as bool? ?? false;
        }).toList();

        newSales.add(LocalSale()
          ..uuid = id
          ..total = (sale['total'] as num?)?.toDouble() ?? 0
          ..paymentMethod = sale['payment_method'] as String? ?? 'cash'
          ..employeeName = sale['employee_name'] as String? ?? ''
          ..isCreditSale = sale['is_credit'] as bool? ?? false
          ..saleOrigin = sale['sale_origin'] as String? ?? 'counter'
          ..tableLabel = sale['table_label'] as String?
          ..items = items
          ..createdAt = DateTime.tryParse(sale['created_at'] as String? ?? '') ??
              DateTime.now()
          ..synced = true);
      }

      if (newSales.isNotEmpty) {
        // insertSales hace UPSERT por uuid (ver database_service_io.dart) —
        // aunque este dedupe por las últimas 500 ventas locales filtre la
        // gran mayoría de repetidos, ya no es la ÚNICA defensa: si una
        // venta del servidor cae fuera de esa ventana (multi-cajero,
        // tienda con +500 ventas), insertSales la actualiza en vez de
        // chocar contra el índice único de Isar.
        await db.insertSales(newSales);
        debugPrint('[SALES_SYNC] Pulled ${newSales.length} sales from server');
      }
    } catch (e) {
      debugPrint('[SALES_SYNC] Pull failed: $e');
    }
  }

  /// Guard de reentrada: syncNow() (timer 30 s) + _onConnectivityChange +
  /// processSale + las 3 pantallas que llaman pushToServer pueden solaparse.
  /// Un doble push es idempotente (el backend devuelve 200 sin doble descuento)
  /// pero desperdicia red y puede doble-marcar; este flag serializa los sweeps.
  static bool _pushInFlight = false;

  /// Push all unsynced local sales to the server.
  static Future<void> pushToServer() async {
    if (_pushInFlight) return;
    _pushInFlight = true;
    try {
      final db = DatabaseService.instance;
      // TODAS las no sincronizadas (sin tope). Antes `getRecentSales(200)`
      // dejaba ventas viejas sin sincronizar fuera del sweep → pérdida.
      final unsynced = await db.getUnsyncedSales();

      if (unsynced.isEmpty) return;

      final api = ApiService(AuthService());
      int synced = 0;

      for (final sale in unsynced) {
        // Guard compartido con el push inmediato del screen
        // (_syncSaleToBackend en pos_screen.dart): si ese camino fire-and-
        // forget ya está subiendo esta misma venta ahora mismo, NO la
        // dupliques aquí. Si termina bien la deja synced=true (este sweep
        // ni la vuelve a ver); si falla la deja synced=false y este sweep
        // la recoge la próxima vuelta del timer de 30 s.
        if (!acquireSalePush(sale.uuid)) {
          debugPrint('[SALES_SYNC] ${sale.uuid} ya en vuelo por otro camino '
              '— se omite para no duplicar el POST');
          continue;
        }
        try {
          // Skip sales with non-UUID ids (legacy timestamp-based)
          if (!sale.uuid.contains('-') || sale.uuid.length < 32) {
            debugPrint('[SALES_SYNC] Skipping non-UUID sale: ${sale.uuid}');
            // Mark as synced to avoid retrying forever
            await db.markSaleSynced(sale);
            continue;
          }

          // Mismo serializador que el camino vivo (_syncSaleToBackend): un item
          // de servicio (productUuid 'service_…') debe viajar como is_service +
          // custom_unit_price, no como producto. Antes se mandaba como producto
          // → el backend no lo encontraba, abortaba la venta entera y NUNCA
          // sincronizaba (pérdida). También enviamos unit_price del precio
          // efectivo persistido (tier ya aplicado).
          final items = sale.items
              .where((i) => !i.isContainerCharge)
              .map(saleSyncItemPayload)
              .where((m) =>
                  m['is_service'] == true ||
                  (m['product_id'] as String).isNotEmpty)
              .toList();

          if (items.isEmpty) {
            debugPrint('[SALES_SYNC] Skipping sale with no valid items: ${sale.uuid}');
            await db.markSaleSynced(sale);
            continue;
          }

          final payload = <String, dynamic>{
            'id': sale.uuid,
            'payment_method': sale.paymentMethod,
            'items': items,
          };
          // Spec 049 (IVA): desglose de IVA congelado por línea → el servidor
          // lo guarda para reportes (no cambia el total cobrado).
          final saleTax =
              sale.items.fold<double>(0, (s, i) => s + (i.taxAmount ?? 0));
          if (saleTax > 0) {
            payload['tax_amount'] = saleTax;
          }
          if (sale.creditAccountId != null &&
              sale.creditAccountId!.isNotEmpty) {
            payload['credit_account_id'] = sale.creditAccountId;
          }
          await api.createSale(payload);

          // Mark as synced
          await db.markSaleSynced(sale);
          synced++;
        } catch (e) {
          // Distinguir error PERMANENTE (el server rechazó el payload) de
          // error TRANSITORIO (red caída, 5xx, timeout). Sin esto, una venta
          // estructuralmente inválida se reintentaba cada 30 s para siempre
          // (el catch viejo solo la dejaba synced=false). 400/422 = el backend
          // la rechazó por contrato → reintentar es inútil: la marcamos
          // sincronizada para drenarla y la logueamos FUERTE para visibilidad.
          // Cualquier otro caso (5xx, red, 401/403 por token vencido) se deja
          // synced=false para reintentar en el próximo sweep.
          final permanent = isPermanentSalePushError(e);
          if (permanent) {
            debugPrint('[SALES_SYNC] ⚠️ Venta RECHAZADA por el servidor '
                '(${(e as AppError).statusCode}) — se descarta de la cola para '
                'no reintentar infinito: ${sale.uuid} → $e');
            await db.markSaleSynced(sale);
          } else {
            debugPrint('[SALES_SYNC] Push transitorio falló para ${sale.uuid} '
                '(reintentará): $e');
          }
          // Continue with next sale — don't block on one failure
        } finally {
          releaseSalePush(sale.uuid);
        }
      }

      if (synced > 0) {
        debugPrint('[SALES_SYNC] Pushed $synced/${unsynced.length} sales to server');
      }
    } catch (e) {
      debugPrint('[SALES_SYNC] Push batch failed: $e');
    } finally {
      _pushInFlight = false;
    }
  }

  /// Full sync: pull then push.
  static Future<void> fullSync() async {
    await pullFromServer();
    await pushToServer();
  }
}

/// Reservas activas de UUIDs de venta que algún camino — el push inmediato
/// fire-and-forget del screen (`_syncSaleToBackend` en pos_screen.dart) o el
/// sweep periódico de [SalesSyncService.pushToServer] — está subiendo AHORA
/// MISMO al backend. Antes cada camino llamaba a `api.createSale` para la
/// misma venta de forma totalmente independiente, confiando ciegamente en
/// que el backend fuera idempotente por UUID (nunca verificado/forzado del
/// lado del cliente): en una conexión lenta, el timer de 30 s podía disparar
/// justo cuando el push inmediato del screen seguía en vuelo y la MISMA
/// venta salía POSTeada casi simultáneamente por los dos caminos.
///
/// `acquireSalePush`/`releaseSalePush` son el guard compartido: CUALQUIER
/// caller que vaya a invocar `api.createSale` para una venta debe reservar
/// su uuid primero con [acquireSalePush]. Si devuelve false, otro camino ya
/// la tiene en vuelo — este caller debe abstenerse de llamar a createSale
/// (la venta queda igual de servida: el dueño actual la marca synced al
/// terminar, o la deja synced=false para que el siguiente sweep la levante
/// si falla). Quien adquiere la reserva DEBE liberarla con
/// [releaseSalePush] en un `finally`.
final Set<String> _salesPushInFlight = <String>{};

/// API pública intencional (NO `@visibleForTesting`): la usan tanto
/// `pos_screen.dart` (push inmediato) como esta misma clase (sweep
/// periódico), en archivos distintos — es el punto de coordinación entre
/// los dos caminos, no un detalle interno expuesto solo para tests.
bool acquireSalePush(String uuid) => _salesPushInFlight.add(uuid);

/// Ver [acquireSalePush].
void releaseSalePush(String uuid) => _salesPushInFlight.remove(uuid);

/// Solo para tests: limpia el guard global entre casos para que no se
/// contaminen entre sí (el Set es de módulo, no de instancia).
@visibleForTesting
void resetSalesPushInFlightForTest() => _salesPushInFlight.clear();

/// True cuando un fallo al subir una venta es PERMANENTE: el servidor rechazó
/// el payload por contrato (HTTP 400/422), así que reintentar cada 30 s es
/// inútil y la venta debe drenarse de la cola (con log fuerte). Cualquier otro
/// error — 5xx, red caída, timeout, 401/403 por token vencido — es TRANSITORIO
/// y debe reintentarse. Spec 047: evita el bucle de reintento infinito que
/// señaló el concilio.
bool isPermanentSalePushError(Object e) {
  return e is AppError && (e.statusCode == 400 || e.statusCode == 422);
}

/// Serializa un item de venta para `/sync/batch` igual que el camino vivo
/// (`_syncSaleToBackend`): un servicio ad-hoc (productUuid 'service_…') viaja
/// como `is_service` + `custom_unit_price`; un producto normal como
/// `product_id` + `unit_price` (precio efectivo persistido).
@visibleForTesting
Map<String, dynamic> saleSyncItemPayload(SaleItemEmbed i) {
  if (i.productUuid.startsWith('service_')) {
    return {
      'quantity': i.quantity,
      'is_service': true,
      'custom_description': i.productName,
      'custom_unit_price': i.unitPrice,
    };
  }
  return {
    'product_id': i.productUuid,
    'quantity': i.quantity,
    'unit_price': i.unitPrice,
  };
}
