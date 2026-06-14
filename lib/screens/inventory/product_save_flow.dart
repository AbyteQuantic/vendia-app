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
Future<ProductSaveOutcome> persistProductOfflineFirst({
  required Future<void> Function() serverWrite,
  required Future<void> Function() saveLocal,
  required Future<void> Function() markPending,
}) async {
  bool serverOk = false;
  try {
    await serverWrite();
    serverOk = true;
  } catch (_) {
    // Sin conexión / backend caído: NO abortamos.
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
