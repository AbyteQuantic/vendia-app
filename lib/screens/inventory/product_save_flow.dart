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
Future<ProductSaveOutcome> persistProductOfflineFirst({
  required Future<void> Function() serverWrite,
  required Future<void> Function() saveLocal,
  required Future<void> Function() markPending,
  Future<bool> Function()? isOnline,
}) async {
  bool serverOk = false;

  final online = isOnline == null ? true : await isOnline();
  if (online) {
    try {
      await serverWrite();
      serverOk = true;
    } catch (_) {
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
