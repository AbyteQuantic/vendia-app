# VendIA Web — estado y limitaciones

Esta carpeta habilita la build web de VendIA (`flutter build web`). La app web
es la **misma app móvil** (diseñada a 360dp): en el navegador se ve como una
app de teléfono, lo cual es intencional — no hay rediseño de escritorio.

## Cómo construir y servir

```bash
flutter build web          # genera build/web/
flutter run -d chrome      # desarrollo con hot-reload en Chrome
```

El output queda en `build/web/` (artefacto estático: `index.html`,
`main.dart.js`, `flutter_bootstrap.js`, `assets/`, `canvaskit/`).

## Limitación principal: persistencia offline DEGRADADA

La Constitución (Art. II — "Offline-first es ley") aplica al **POS móvil**.
En web, el almacenamiento offline queda **degradado** por una incompatibilidad
de plataforma:

- El paquete **Isar** (base de datos local offline-first) depende de
  `dart:ffi` y su generador emite esquemas con literales enteros de 64 bits
  que **dart2js no puede compilar a JavaScript**
  (`The integer literal ... can't be represented exactly in JavaScript`).
- Por lo tanto la build web **no puede usar el backend Isar nativo**.

### Cómo se resolvió (imports condicionales)

Se introdujo una fachada por plataforma usando
`export '...' if (dart.library.html) '..._web.dart';`:

| Archivo (lo que importa el resto de la app) | Móvil/escritorio        | Web                       |
|---------------------------------------------|-------------------------|---------------------------|
| `database/database_service.dart`            | `database_service_io.dart` (Isar real) | `database_service_web.dart` (stub en memoria) |
| `database/collections/local_*.dart`         | `local_*_io.dart` (clase con `@collection` Isar + `*_io.g.dart`) | `local_*_web.dart` (clase plana sin Isar) |

- En **móvil/escritorio** (`dart.library.io`) no cambia nada: Isar real,
  persistencia completa, esquemas generados por `build_runner`.
- En **web** (`dart.library.html`) `DatabaseService` es un stub **en memoria**:
  las colecciones (productos, ventas, clientes, fiados, mesas, métodos de
  pago, cola de sync) viven en `List`s + `StreamController`s durante la
  sesión. Las consultas y los streams reactivos funcionan **dentro de la
  sesión**, pero **un refresco del navegador pierde los datos locales** — no
  hay IndexedDB ni persistencia real.

### Qué sigue funcionando en web

- Login, navegación, dashboards y todo lo que va contra el backend Go.
- Ventas, fiados y mesas durante la sesión (sincronizan contra el backend).
- Los streams reactivos del POS (stock negativo, mesas abiertas, etc.).

### Qué queda degradado en web (aceptable para v1)

- **Sin persistencia offline real**: cerrar/refrescar la pestaña vacía el
  almacén local. El modo offline-first completo es exclusivo de móvil.
- La cola de operaciones pendientes (`PendingOperation`) tampoco sobrevive a
  un refresco.

## Otros plugins

`flutter_secure_storage` emite advertencias `dart:html unsupported` durante la
compilación web; **no son fatales** — el plugin trae su propia implementación
web (`flutter_secure_storage_web`) y la build termina bien. Los plugins de
cámara/escáner (`mobile_scanner`, `image_picker`) y audio (`record`) traen
soporte web propio o degradan con gracia.

## Próximo paso opcional (fuera de alcance de v1)

Para persistencia offline en web sin Isar: portar `database_service_web.dart`
a IndexedDB (p. ej. `package:idb_shim` o `shared_preferences` para datos
pequeños). No es necesario para liberar la web v1.
