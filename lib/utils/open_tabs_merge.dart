// Spec: specs/053-... (sync offline de mesas) — lado PULL.
//
// Lógica PURA del merge "traer mesas abiertas del servidor" (GET /tables/open)
// contra el estado local en Isar. Se extrae aquí, sin tocar Isar, para poder
// fijarla con unit tests en `flutter test` (Isar necesita libs nativas/E2E en
// device — patrón ya usado en h10_pending_ops_tenant_preservation_test).
//
// El I/O (leer/escribir Isar) vive en DatabaseService.applyServerOpenTabs, que
// delega TODA la decisión a estas funciones.

import '../database/collections/local_table_tab.dart';

/// Qué hacer con una mesa abierta que reporta el servidor, frente a lo local.
enum OpenTabMergeAction { create, replace, skip }

/// Metadata mínima del servidor para decidir el merge (LWW por mesa).
class OpenTabServerMeta {
  final String label;
  final DateTime updatedAt;
  const OpenTabServerMeta({required this.label, required this.updatedAt});
}

/// Metadata mínima local para decidir el merge.
class OpenTabLocalMeta {
  final DateTime updatedAt;
  final bool synced;
  const OpenTabLocalMeta({required this.updatedAt, required this.synced});
}

/// LWW por mesa. Para cada mesa que el servidor reporta abierta decide:
/// - **create**: no existe local (este dispositivo no conocía el label).
/// - **skip** (local sin sincronizar): hay cambios locales que aún no suben
///   (`synced == false`) → NO se pisan; el push los reconcilia después.
/// - **replace**: lo local ya está sincronizado y el servidor es más nuevo.
/// - **skip**: lo local está al día o es más nuevo que el servidor.
///
/// Solo decide sobre las mesas que vienen del servidor. Las mesas locales que
/// el servidor ya NO reporta (cerradas en otro dispositivo) NO se tocan aquí —
/// se cierran por su propio camino (applyServerTabSnapshot/closeTabIfPaid),
/// para no borrar por error una cuenta recién abierta sin subir.
Map<String, OpenTabMergeAction> planOpenTabsMerge({
  required List<OpenTabServerMeta> server,
  required Map<String, OpenTabLocalMeta> localByLabel,
}) {
  final out = <String, OpenTabMergeAction>{};
  for (final s in server) {
    final local = localByLabel[s.label];
    if (local == null) {
      out[s.label] = OpenTabMergeAction.create;
    } else if (!local.synced) {
      out[s.label] = OpenTabMergeAction.skip;
    } else if (s.updatedAt.isAfter(local.updatedAt)) {
      out[s.label] = OpenTabMergeAction.replace;
    } else {
      out[s.label] = OpenTabMergeAction.skip;
    }
  }
  return out;
}

/// Parsea un timestamp del servidor (ISO-8601) de forma tolerante.
/// Devuelve null si viene vacío o ilegible — el caller decide el default
/// (epoch para no pisar local en LWW; now() para el `updatedAt` del tab nuevo).
DateTime? parseServerTimestamp(dynamic raw) {
  if (raw is DateTime) return raw;
  if (raw is! String || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

/// Construye un `LocalTableTab` FRESCO desde el JSON de GET /tables/open
/// (un OrderTicket abierto). Mapea los `items` (product_uuid/product_name/
/// quantity/unit_price) y recomputa `grossTotal` desde los ítems para mantener
/// la invariante local (grossTotal == suma de ítems).
///
/// `abonosTotal` se deja en 0: el endpoint /tables/open no trae los abonos, y
/// el saldo exacto se reconcilia con applyServerTabSnapshot al abrir la mesa.
/// `synced = true` porque viene confirmado por el servidor.
LocalTableTab localTableTabFromServerJson(Map<String, dynamic> json) {
  final label = (json['label'] as String?)?.trim() ?? '';
  final rawItems = (json['items'] as List?) ?? const [];
  final items = rawItems
      .whereType<Map<String, dynamic>>()
      .map((it) => LocalTabItem()
        ..productUuid = (it['product_uuid'] as String?) ?? ''
        ..productName = (it['product_name'] as String?) ?? ''
        ..quantity = (it['quantity'] as num?)?.toInt() ?? 0
        ..unitPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0
        ..sentAt = null)
      .toList();
  final grossTotal =
      items.fold<double>(0.0, (s, i) => s + i.unitPrice * i.quantity);
  return LocalTableTab()
    ..label = label
    ..sessionToken = json['session_token'] as String?
    ..orderId = json['order_id'] as String?
    ..items = items
    ..grossTotal = grossTotal
    ..abonosTotal = 0.0
    ..pendingBalance = grossTotal
    ..status = (json['status'] as String?) ?? 'nuevo'
    ..updatedAt = parseServerTimestamp(json['updated_at']) ?? DateTime.now()
    ..synced = true;
}
