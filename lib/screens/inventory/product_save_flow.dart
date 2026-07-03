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
