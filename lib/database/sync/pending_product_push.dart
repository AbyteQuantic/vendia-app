// Spec: specs/047-offline-sync-contract/spec.md
//
// Registro liviano de los UUIDs de productos creados OFFLINE que aún no han
// llegado al servidor. Vive en SharedPreferences (no en Isar) para no tocar el
// esquema. Sirve a dos cosas:
//   * `replaceAllProducts` lo consulta para NO borrar un producto offline
//     cuando llega el catálogo del servidor (que todavía no lo conoce),
//   * el sync de Spec 047 lo usará para reintentar el push y luego limpiarlo.

import 'package:shared_preferences/shared_preferences.dart';

class PendingProductPush {
  static const _key = 'vendia_pending_product_push_uuids';

  /// Marca un producto como pendiente de subir.
  static Future<void> add(String uuid) async {
    if (uuid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final set = prefs.getStringList(_key)?.toSet() ?? <String>{};
    if (set.add(uuid)) {
      await prefs.setStringList(_key, set.toList());
    }
  }

  /// Quita un producto del registro (ya se subió con éxito).
  static Future<void> remove(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    final set = prefs.getStringList(_key)?.toSet() ?? <String>{};
    if (set.remove(uuid)) {
      await prefs.setStringList(_key, set.toList());
    }
  }

  /// Conjunto actual de UUIDs pendientes (vacío si ninguno).
  static Future<Set<String>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key)?.toSet() ?? <String>{};
  }
}
