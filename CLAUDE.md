# VendIA Frontend (vendia_pos) — Claude Code Context

App móvil Flutter del POS VendIA. Es la cara que ve el tendero todos los días.

> Parte del workspace **VendIA**. Antes de tocar código lee, en orden:
> [`../CONSTITUTION.md`](../CONSTITUTION.md) → [`../AGENTS.md`](../AGENTS.md) → este archivo.
> Si vas a tocar `lib/screens/**` o `lib/widgets/**`, lee **además**
> [`DESIGN.md`](DESIGN.md) y [`UI_RULES.md`](UI_RULES.md).

## Stack

- **Flutter / Dart** — SDK `>=3.3.0 <4.0.0`
- **Estado:** Provider
- **HTTP:** Dio (contra el backend Go — ver [`BACKEND_CONTRACT_v2.md`](BACKEND_CONTRACT_v2.md))
- **DB local / offline:** Isar (solo móvil — ver § Web)
- **Plataformas:** Android (prioridad — gama baja), iOS y **Web**

## Estructura

```
lib/
  config/      → configuración y entorno
  core/        → utilidades transversales
  database/    → Isar (DB local offline-first)
  models/      → modelos de datos
  screens/     → pantallas (lee UI_RULES.md antes de tocar)
  services/    → clientes HTTP (Dio) y lógica de sincronización
  theme/       → tema y estilos
  utils/       → helpers
  widgets/     → componentes reutilizables
test/                → unit y widget tests
integration_test/     → pruebas de integración / E2E
```

## Audiencia y restricciones (Constitución Art. I)

Tenderos 50+ en Android de gama baja, pantallas estrechas (**360dp**). Un
overflow rompe la funcionalidad, no es cosmético. Cero fricción cognitiva:
defaults sobre preguntas, objetivos táctiles grandes, todo en español.

## Desarrollo guiado por especificación (Spec-Driven)

Ningún cambio de pantalla, flujo o contrato entra sin un `spec` en `../specs/`.
Flujo: **specify → clarify → plan → tasks → implement → analyze** (slash
commands en `../.claude/commands/`).

Adaptación a este repo (Flutter):
- **RED:** widget/unit test en `test/` (o `integration_test/` para flujos E2E)
  que falla por la razón correcta.
- **GREEN:** pantalla/widget/servicio mínimo que la hace pasar.
- **REFACTOR:** extrae widgets reutilizables a `lib/widgets/`; archivos < 800 líneas.
- **Offline (Art. II):** todo flujo de venta debe especificar su comportamiento
  sin conexión — escritura en Isar + cola de sync, nunca asumir red.
- **Verificación:** `flutter analyze` + `flutter test` en verde, cobertura ≥ 80%.
- **Trazabilidad:** primera línea de cada archivo nuevo → `// Spec: specs/NNN-slug/spec.md`.

## Web — plataforma, despliegue y limitaciones

- La plataforma web está habilitada; la app web se sirve en **`vendia.store`**
  (proyecto Vercel `vendia-app`).
- ⚠️ **NO auto-despliega al mergear a `main`.** Hay que `flutter build web
  --release --dart-define=API_BASE_URL=https://api.vendia.store` y
  `vercel deploy --prod`. El workflow `.github/workflows/deploy-web.yml` lo
  automatiza cuando se agregue el secret `VERCEL_TOKEN`. **Mergear ≠ desplegar.**
- **Limitación offline:** Isar es **solo móvil**. En web `DatabaseService` es un
  stub en memoria (`database_service_web.dart`) — los datos locales se pierden
  al refrescar. Detalle en [`web/README_WEB.md`](web/README_WEB.md).
- **Imágenes cross-platform:** nunca `dart:io File` ni `XFile.path` en el camino
  web (no hay sistema de archivos) — usar `XFile.readAsBytes()` +
  `MultipartFile.fromBytes`. (Causa del bug del logo, F007.)
- **iOS:** el proyecto está configurado, pero compilar/desplegar requiere un Mac
  con Xcode + cuenta Apple Developer.
- **Verifica los cambios en `vendia.store` desplegado**, no en un build local
  (Constitución Art. XII).

## Reglas de UI (resumen — el detalle está en UI_RULES.md)

- Máximo 2 acciones laterales en un header; 3+ → `AppBar.actions` con `more_vert`.
- Diseñar y probar contra 360dp de ancho.
- Texto de cara al usuario: español colombiano, sin jerga.
