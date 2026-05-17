// Facade: selecciona la implementación de la colección según la plataforma.
//
// En móvil/escritorio (`dart.library.io`) usa la implementación Isar real
// (`local_credit_io.dart`), con esquema offline-first persistente.
//
// En web (`dart.library.html`) usa un modelo plano sin Isar
// (`local_credit_web.dart`): la persistencia offline queda DEGRADADA en web
// porque el backend Isar depende de `dart:ffi` y de literales enteros de
// 64 bits que dart2js no puede compilar. Ver web/README_WEB.md.
export 'local_credit_io.dart'
    if (dart.library.html) 'local_credit_web.dart';
