// Spec: specs/047-offline-sync-contract/spec.md (creación de producto offline)
//
// Invariante offline-first del guardado de producto, extraída para poder
// probarla sin acoplar la pantalla a Dio/Isar. El bug previo hacía el guardado
// LOCAL después de la llamada de red dentro del mismo try: sin conexión la red
// lanzaba, se saltaba al catch y el producto (con su foto) se perdía — pero la
// UI mostraba "guardado". Aquí la red es best-effort y el local SIEMPRE persiste.

class ProductSaveOutcome {
  final bool serverOk;
  final bool savedLocally;
  final bool markedPending;
  const ProductSaveOutcome({
    required this.serverOk,
    required this.savedLocally,
    required this.markedPending,
  });
}

/// Orquesta el guardado offline-first:
///   1. intenta [serverWrite] (puede lanzar si no hay red) — best effort,
///   2. ejecuta [saveLocal] SIEMPRE (el producto nunca se pierde),
///   3. si el servidor no confirmó, ejecuta [markPending] (protege el producto
///      del pull destructivo y lo marca para subir luego).
///
/// [isOnline] (opcional): si se pasa y devuelve `false`, se OMITE [serverWrite]
/// por completo. Sin esto, guardar offline bloquea ~30s esperando el timeout
/// del socket antes de caer al guardado local; conociendo el estado de red lo
/// saltamos y guardamos local al instante. Si es null, se asume online (intenta
/// la red como antes — retrocompatible).
///
/// [isFatal] (opcional, auditoría 2026-07-03): distingue un error de RED
/// (best-effort, cae a local+pendiente como siempre) de un error DEL
/// SERVIDOR que el tendero debe resolver antes de guardar nada — el caso
/// real: el backend rechaza con 409 "ya existe un producto con ese nombre"
/// (ver ApiService.createProduct). Guardarlo local+pendiente en ese caso
/// crearía OTRA copia del duplicado que el servidor ya rechazó. Cuando
/// [isFatal] devuelve `true` para el error, éste se RE-LANZA sin tocar
/// [saveLocal]/[markPending] — el caller decide qué hacer (ej. mostrar un
/// diálogo). Por defecto null → comportamiento anterior sin cambios.
Future<ProductSaveOutcome> persistProductOfflineFirst({
  required Future<void> Function() serverWrite,
  required Future<void> Function() saveLocal,
  required Future<void> Function() markPending,
  Future<bool> Function()? isOnline,
  bool Function(Object error)? isFatal,
}) async {
  bool serverOk = false;

  final online = isOnline == null ? true : await isOnline();
  if (online) {
    try {
      await serverWrite();
      serverOk = true;
    } catch (e) {
      if (isFatal != null && isFatal(e)) rethrow;
      // Backend caído / red intermitente: NO abortamos, caemos a local.
    }
  }

  await saveLocal();

  if (!serverOk) {
    await markPending();
  }

  return ProductSaveOutcome(
    serverOk: serverOk,
    savedLocally: true,
    markedPending: !serverOk,
  );
}

class ProductUpdateOutcome {
  final bool serverOk;
  const ProductUpdateOutcome({required this.serverOk});
}

/// Orquesta la EDICIÓN offline-first de un producto ya existente.
///
/// Bug previo (auditoría 2026-07-03): `_EditProductSheetState._save()` en
/// manage_inventory_screen.dart llamaba a `serverWrite` directo; si fallaba
/// Y el widget ya se había desmontado (el tendero navegó a otro producto
/// antes de que la respuesta volviera — muy real editando cientos de
/// referencias con señal intermitente), el `catch` empezaba con
/// `if (!mounted) return` y el cambio se perdía SIN RASTRO: ni se guardaba
/// local, ni quedaba en ninguna cola, ni el tendero se enteraba.
///
/// Aquí [serverWrite] es best-effort; si falla POR CUALQUIER MOTIVO, se
/// llama a [enqueueRetry] (que el caller conecta a la cola genérica de sync,
/// `SyncService.enqueue` — el mismo camino ya usado por fiado/cliente, y que
/// el backend YA soporta para `entity: product, action: update` con
/// Last-Write-Wins). El error nunca se relanza: el llamador decide cómo
/// avisar (o no) sin arriesgar perder el dato — el motor de sync ya
/// descarta un payload que el servidor rechaza por contrato tras
/// `maxSyncOpRetries` intentos (sync_service.dart), así que no hace falta
/// distinguir aquí error permanente de transitorio.
Future<ProductUpdateOutcome> persistProductUpdateOfflineFirst({
  required Future<void> Function() serverWrite,
  required Future<void> Function() enqueueRetry,
}) async {
  try {
    await serverWrite();
    return const ProductUpdateOutcome(serverOk: true);
  } catch (_) {
    await enqueueRetry();
    return const ProductUpdateOutcome(serverOk: false);
  }
}
