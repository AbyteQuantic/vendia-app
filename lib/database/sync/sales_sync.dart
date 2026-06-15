import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
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
        await db.insertSales(newSales);
        debugPrint('[SALES_SYNC] Pulled ${newSales.length} sales from server');
      }
    } catch (e) {
      debugPrint('[SALES_SYNC] Pull failed: $e');
    }
  }

  /// Push all unsynced local sales to the server.
  static Future<void> pushToServer() async {
    try {
      final db = DatabaseService.instance;
      final allSales = await db.getRecentSales(limit: 200);
      final unsynced = allSales.where((s) => !s.synced).toList();

      if (unsynced.isEmpty) return;

      final api = ApiService(AuthService());
      int synced = 0;

      for (final sale in unsynced) {
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
          debugPrint('[SALES_SYNC] Push failed for ${sale.uuid}: $e');
          // Continue with next sale — don't block on one failure
        }
      }

      if (synced > 0) {
        debugPrint('[SALES_SYNC] Pushed $synced/${ unsynced.length} sales to server');
      }
    } catch (e) {
      debugPrint('[SALES_SYNC] Push batch failed: $e');
    }
  }

  /// Full sync: pull then push.
  static Future<void> fullSync() async {
    await pullFromServer();
    await pushToServer();
  }
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
