// Spec: specs/047-offline-sync-contract/spec.md
//
// Bug real (auditoría 2026-07-03): un producto creado SIN internet se
// guardaba local + PendingProductPush.add(id) lo marcaba "pendiente", pero
// nada volvía a reintentar el POST — remove() nunca se invocaba desde ningún
// camino vivo. El producto quedaba protegido de que el pull del servidor lo
// borrara localmente (replaceAllProducts), pero JAMÁS llegaba al servidor:
// invisible en otras sedes/reportes/backups, y perdido para siempre si el
// celular se pierde o se reinstala antes de recuperar señal.
//
// Mismo patrón que SalesSyncService.pushToServer (sales_sync.dart): sweep
// best-effort por item, distingue error PERMANENTE (el servidor rechaza el
// payload por contrato → reintentar es inútil, se drena) de TRANSITORIO
// (red/5xx → se reintenta en el próximo sweep de syncNow()).

import 'package:flutter/foundation.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../database_service.dart';
import '../collections/local_product.dart';
import 'pending_product_push.dart';

class ProductPushSync {
  static bool _pushInFlight = false;

  /// Push de todos los productos pendientes (PendingProductPush) al servidor.
  static Future<void> pushToServer() async {
    if (_pushInFlight) return;
    _pushInFlight = true;
    try {
      final pending = await PendingProductPush.all();
      if (pending.isEmpty) return;

      final db = DatabaseService.instance;
      final api = ApiService(AuthService());
      int synced = 0;

      for (final uuid in pending) {
        try {
          final product = await db.getProductByUuid(uuid);
          if (product == null) {
            // Ya no existe localmente (el tendero lo borró offline) — nada
            // que subir; deja de protegerlo/reintentarlo.
            await PendingProductPush.remove(uuid);
            continue;
          }
          // CreateProduct es idempotente por id (Feature 014): si este mismo
          // producto ya llegó al servidor en un intento anterior cuyo
          // response se perdió, el backend responde 200 con el existente en
          // vez de duplicar — un reintento nunca crea una copia.
          await api.createProduct(productSyncPayload(product));
          await PendingProductPush.remove(uuid);
          synced++;
        } catch (e) {
          if (isPermanentProductPushError(e)) {
            debugPrint('[PRODUCT_SYNC] ⚠️ Producto RECHAZADO por el servidor '
                '(${(e as AppError).statusCode}/${e.errorCode}) — se descarta '
                'de la cola para no reintentar infinito: $uuid → $e');
            await PendingProductPush.remove(uuid);
          } else {
            debugPrint('[PRODUCT_SYNC] Push transitorio falló para $uuid '
                '(reintentará): $e');
          }
          // Sigue con el siguiente — uno malo no bloquea a los demás.
        }
      }

      if (synced > 0) {
        debugPrint('[PRODUCT_SYNC] Pushed $synced/${pending.length} products to server');
      }
    } catch (e) {
      debugPrint('[PRODUCT_SYNC] Push batch failed: $e');
    } finally {
      _pushInFlight = false;
    }
  }
}

/// Payload de creación a partir del producto guardado local. Usa "id" (no
/// "uuid") y solo los campos que CreateProduct acepta (products.go Request) —
/// mismas claves que el camino vivo en create_product_screen.dart.
@visibleForTesting
Map<String, dynamic> productSyncPayload(LocalProduct p) => {
      'id': p.uuid,
      'name': p.name,
      'price': p.price,
      'stock': p.stock,
      'min_stock': p.minStock,
      'requires_container': p.requiresContainer,
      'container_price': p.containerPrice,
      'is_menu_item': p.isMenuItem,
      if (p.imageUrl != null && p.imageUrl!.isNotEmpty) 'image_url': p.imageUrl,
      if (p.barcode != null && p.barcode!.isNotEmpty) 'barcode': p.barcode,
      if (p.presentation != null) 'presentation': p.presentation,
      if (p.content != null) 'content': p.content,
      if (p.category != null) 'category': p.category,
      if (p.characteristics != null) 'characteristics': p.characteristics,
      if (p.expiryDate != null)
        'expiry_date': '${p.expiryDate!.year.toString().padLeft(4, '0')}-'
            '${p.expiryDate!.month.toString().padLeft(2, '0')}-'
            '${p.expiryDate!.day.toString().padLeft(2, '0')}',
    };

/// True cuando el servidor rechazó el producto por CONTRATO — payload
/// inválido (400/422) o un duplicado real de nombre+presentación creado
/// mientras tanto por otro camino (409 duplicate_product, Spec de auditoría
/// 2026-07-03). Reintentar cada 30 s es inútil en ambos casos: se drena de
/// la cola con log fuerte. Cualquier otro error (5xx, red, timeout, 401/403
/// por token vencido) es TRANSITORIO y se reintenta en el próximo sweep.
@visibleForTesting
bool isPermanentProductPushError(Object e) {
  if (e is! AppError) return false;
  if (e.errorCode == 'duplicate_product') return true;
  return e.statusCode == 400 || e.statusCode == 422;
}
