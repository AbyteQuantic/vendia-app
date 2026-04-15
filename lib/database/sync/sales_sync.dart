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
          ..items = items
          ..createdAt = DateTime.tryParse(sale['created_at'] as String? ?? '') ??
              DateTime.now()
          ..synced = true);
      }

      if (newSales.isNotEmpty) {
        await db.isar.writeTxn(() async {
          for (final sale in newSales) {
            await db.isar.localSales.put(sale);
          }
        });
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
          await api.createSale({
            'id': sale.uuid,
            'payment_method': sale.paymentMethod,
            'items': sale.items
                .where((i) => !i.isContainerCharge)
                .map((i) => {
                      'product_id': i.productUuid,
                      'quantity': i.quantity,
                    })
                .toList(),
          });

          // Mark as synced
          await db.isar.writeTxn(() async {
            sale.synced = true;
            await db.isar.localSales.put(sale);
          });
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
