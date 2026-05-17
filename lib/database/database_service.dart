// Fachada de DatabaseService: selecciona la implementación según plataforma.
//
// - Móvil/escritorio (`dart.library.io`): database_service_io.dart, respaldado
//   por Isar (offline-first persistente, Constitución Art. II).
// - Web (`dart.library.html`): database_service_web.dart, un stub en memoria.
//   Isar no compila a web (depende de `dart:ffi` y de literales enteros de
//   64 bits que dart2js rechaza), así que en web la persistencia offline
//   queda DEGRADADA: las colecciones viven solo durante la sesión y no
//   sobreviven a un refresco del navegador. Ver web/README_WEB.md.
//
// El resto de la app importa SIEMPRE este archivo; nunca las variantes
// `_io`/`_web` directamente.
export 'database_service_io.dart'
    if (dart.library.html) 'database_service_web.dart';
