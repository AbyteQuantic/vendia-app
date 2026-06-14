// Spec: specs/047-offline-sync-contract/spec.md (H1 — pull no destructivo)
//
// Merge del catálogo que llega del servidor contra el set local, SIN perder
// estado que solo vive en el dispositivo. El bug previo (`replaceAllProducts`)
// hacía `clear()` + `putAll(server)`, lo que:
//   1. reseteaba `reservedStock` a 0 → una mesa abierta perdía su reserva de
//      stock y se podía sobrevender, y
//   2. borraba productos creados offline que aún no llegan al servidor.
//
// Reglas del merge:
//   * el servidor es la verdad para precio/stock/foto/etc. de un producto que
//     ambos conocen,
//   * `reservedStock` es un concepto LOCAL (reservas de mesa) → se conserva del
//     row local por uuid,
//   * un producto local cuyo uuid NO viene del servidor se ELIMINA (el server lo
//     borró)… EXCEPTO si está en [protectedUuids] (creado offline, pendiente de
//     subir) — ese sobrevive hasta que el sync lo empuje (Spec 047).

import '../collections/local_product.dart';

List<LocalProduct> mergeServerProducts({
  required List<LocalProduct> existing,
  required List<LocalProduct> incoming,
  Set<String> protectedUuids = const {},
}) {
  final existingByUuid = {for (final p in existing) p.uuid: p};

  // Dedup del payload del servidor por uuid (último gana = más fresco) y
  // arrastre del reservedStock local.
  final result = <String, LocalProduct>{};
  for (final p in incoming) {
    final local = existingByUuid[p.uuid];
    if (local != null) {
      p.reservedStock = local.reservedStock;
    }
    result[p.uuid] = p;
  }

  // Protege los productos locales no presentes en el servidor que están
  // pendientes de subir (creados offline). El resto se considera borrado
  // server-side y NO se reinserta.
  for (final p in existing) {
    if (!result.containsKey(p.uuid) && protectedUuids.contains(p.uuid)) {
      result[p.uuid] = p;
    }
  }

  return result.values.toList();
}
