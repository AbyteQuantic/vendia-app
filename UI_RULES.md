# UI Rules — vendia-app (Flutter)

Guardrails específicos de Flutter que NO captura `DESIGN.md`. Estas reglas
existen porque la audiencia (tenderos 50+ en Android gama baja) usa pantallas
estrechas (360dp), no actualiza la app frecuentemente, y un overflow rompe la
funcionalidad — no es solo cosmético.

> Cualquier agente (humano o IA) que toque `lib/screens/**` o `lib/widgets/**`
> debe leer este archivo + `DESIGN.md` + **[`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md)**
> antes de empezar.

## 0. 🏆 REGLA DE ORO — Design System (HARD)

La **fuente única de verdad** del aspecto es [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md).
Es OBLIGATORIO antes de crear/ajustar cualquier UI:

- **Tokens centralizados:** colores/tipografía/espaciado SOLO desde `app_theme.dart`
  + `AppUI` (`app_ui.dart`). Prohibido hardcodear `Color(0x..)`, fontSize sueltos
  o `EdgeInsets` mágicos en pantallas.
- **Componentes del kit:** use `AppButton`, `SoftCard`, `InsetGroupedList`,
  `glassAppBar`. **Nunca** `ElevatedButton`/`OutlinedButton` crudos en pantallas
  (su theme legacy de 22px/64dp parte el texto en 360dp — causa real del bug del
  modal de voz, 2026-06-27).
- **Cero overflow / cero texto partido a 360dp**; botones de UNA línea.
- **Marca:** acción = `AppTheme.primary` (azul de marca); logo y fuente oficiales.

Pase el **checklist** de `DESIGN_SYSTEM.md` antes de dar una pantalla por terminada.

## 1. Headers y AppBars

**Regla:** un header NO puede tener más de **2 acciones laterales** en su Row
principal. Si necesitas 3+, usa `AppBar.actions` con un `IconButton(more_vert)`
que abre un popup menu.

**Por qué:** en pantallas 360dp el saludo + nombre de propietario ya consume
60% del ancho. Tres iconos (account + bell + storeStatus) compiten por el 40%
restante y rompen el layout — el texto de la izquierda termina envuelto en
"¡Buen / os días! / B... / Don / Brayan".

```dart
// MAL — Row inline con 3+ widgets a la derecha
Row(children: [
  Expanded(child: greeting),
  AccountButton(),
  BellWidget(),
  StatusPill(),
])

// BIEN — AppBar con actions colapsables
AppBar(
  title: greeting,
  actions: [
    StatusPill(),                              // máximo 1 widget visible
    IconButton(                                // resto en menú
      icon: Icon(Icons.more_vert),
      onPressed: _showHeaderMenu,
    ),
  ],
)
```

## 2. Texto de longitud variable

**Regla:** Cualquier `Text` que muestre datos del usuario (nombre, negocio,
producto) en un row con ancho limitado DEBE envolverse en `Flexible` +
`FittedBox(fit: BoxFit.scaleDown)` ó usar `maxLines: 1` + `overflow: TextOverflow.ellipsis`.

**Por qué:** "Don Brayan" cabe en un mock con un nombre corto; "Distribuidora
Comercial Hermanos Gutierrez SAS" no. La app ya tiene tenants con nombres de
40+ caracteres en producción.

```dart
// MAL
Text(widget.businessName, style: TextStyle(fontSize: 18))

// BIEN
Text(
  widget.businessName,
  style: TextStyle(fontSize: 18),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
)
```

## 3. Pruebas de layout obligatorias

Cada pantalla nueva o modificada DEBE renderizar correctamente en estos tres
viewports antes de hacer push:

| Dispositivo | Resolución lógica | Por qué |
|---|---|---|
| Android gama baja | 360 × 640 dp | Mayoría de Huawei FRL / Honor / Tecno en producción |
| Android estándar | 411 × 891 dp | Pixel 7 / Samsung A-series |
| Tablet horizontal | 800 × 1280 dp | Algunos restaurantes usan tablet POS |

**Cómo verificar:**
```bash
# 360dp — el viewport que más rompe en producción
flutter run -d emulator-5554 --device-vm-service-port=8181
# Cambia tamaño en runtime via Dart DevTools → Layout Explorer
```

Si no puedes probar manualmente en los tres, agrega un `golden test` con
`testWidgets` + `binding.window.physicalSize` para los tres tamaños.

## 4. Botones flotantes y CTAs grandes

**Regla:** ningún botón al fondo de pantalla excede el 92% del ancho del padre,
y siempre tiene **24px** de margen inferior + **20px** lateral. Nunca uses
`width: double.infinity` sin un `Padding` envolvente.

**Por qué:** el botón "Registrar nueva venta" se solapa con el contenido y
queda contra el borde físico — los gestos de "back" del sistema lo activan
accidentalmente.

```dart
// BIEN
SafeArea(
  minimum: EdgeInsets.fromLTRB(20, 0, 20, 24),
  child: ElevatedButton(...),
)
```

## 5. Iconos y áreas de toque

- Iconos decorativos: 20–24dp.
- Iconos interactivos (IconButton): tap-area mínima 48×48dp, ícono visual 24dp.
- Botones secundarios circulares (avatar, pill): mínimo **40×40dp** con
  padding interior. Nunca un círculo de 32dp tappable — se pierde el target
  con dedos gruesos.

## 6. Colores fuera de la paleta = bug

Si un widget pinta un color hex literal que NO está en `app_theme.dart`,
es un bug. Mover el color al theme o usar uno existente. Excepción única:
banderas internacionales en pantallas i18n.

```dart
// MAL
Container(color: Color(0xFFE5E7EB))

// BIEN
Container(color: AppTheme.surfaceGrey)
```

## 7. Spacing en múltiplos de 4

Padding y margins en `EdgeInsets.*` deben usar 4, 8, 12, 16, 20, 24, 32, 48.
Cualquier `padding: 13` o `margin: 17` es un error de copia/pega — si el
diseño realmente lo necesita, se discute en code review.

## 8. Estados de carga y error

Toda pantalla que haga fetch de red tiene 3 estados visibles:
1. **Loading** — `CircularProgressIndicator` centrado, NUNCA pantalla en blanco.
2. **Empty** — ilustración + texto en español plano + CTA para recuperar
   ("No hay ventas hoy. ¡Registre la primera!"). NUNCA "No data".
3. **Error** — mensaje en español + botón "Reintentar". NUNCA exception traces.

## 9. Diálogos y bottom sheets

- **Confirmaciones destructivas** (cerrar sesión, borrar, vaciar carrito):
  `AlertDialog` con dos botones distintos. El destructivo va a la DERECHA con
  `AppTheme.error`.
- **Selección de opciones** (escoger método de pago, seleccionar cliente):
  `showModalBottomSheet` — ocupa menos viewport y es más fácil de cerrar
  con el pulgar.
- Nunca uses `showDialog` para una lista de >3 opciones — usa bottom sheet.

## 10. Test screenshots antes de mergear

Para cualquier PR que toca `lib/screens/**` o `lib/widgets/**`, adjunta al
PR description **dos capturas mínimo**: una en 360dp y otra en 411dp.
La descripción del PR sin captura visual es razón suficiente para devolver.

## 11. Español neutral y profesional — NUNCA voseo ni regionalismos

**Regla:** todo copy visible al usuario va en **español neutral**, tono
formal/profesional, **modo USTED** o impersonal. Prohibido el voseo
rioplatense, las contracciones informales y los regionalismos.

| ❌ NO usar | ✅ Usar |
|-----------|---------|
| `Descubrí más opciones` | `Descubre más opciones` |
| `Activá las que necesites` | `Active las que necesite` |
| `Tocá para enviar` | `Toque para enviar` |
| `Mirá tus ventas` | `Vea sus ventas` |
| `Vas a ver un carrusel` | `Verá un carrusel` |
| `Sumate a Pro` | `Únase a Pro` |
| `Cuándo tenés inventario bajo` | `Cuando tenga inventario bajo` |
| `Ingresá tu PIN` | `Ingrese su PIN` |
| `Acordate de cobrar` | `Recuerde cobrar` |
| `chévere`, `bacano`, `che`, `joya`, `posta` | (eliminar — son regionalismos) |

**Por qué:** el target es Colombia (formal por defecto) + LatAm general.
El voseo argentino se lee como extranjero o poco profesional para el
tendero colombiano 50+. El modo USTED + tono impersonal sirven a todos
los dialectos sin sonar familiar de más.

**Cómo verificar antes de mergear:**

```bash
# Sweep rápido de voseo en copy nuevo:
grep -rnE "(tocá|mirá|sumá|activá|ingresá|escribí|hacé|andá|sentí|guardá|elegí|escogé|empezá|recordá|usá|probá|cerrá|abrí|comprá|vendé|pagá|cobrá|enviá|mandá|llamá|ajustá|configurá|apretá|cliqueá|recibí|añadí|descubrí|preguntale|escribile|prendelo)" lib/
```

Si retorna cualquier match en código nuevo, traducir a USTED antes de
mergear. Las viejas se van limpiando incrementalmente — al tocar una
pantalla, normalizar su copy de paso.

**Acentos diacríticos**: ojo con palabras como `Descubrí` (puede ser
imperativo voseo *o* pretérito en 1ª persona). En copy de UI casi
siempre es imperativo — usar el patrón USTED. Si fuera pretérito
legítimo, revisar contexto.

---

## Validación automática

```bash
# Tokens visuales (DESIGN.md)
npx @google/design.md lint DESIGN.md

# Análisis estático Flutter
flutter analyze

# Tests de widget (incluye golden tests)
flutter test
```

Estas tres deben pasar verde antes de merge a `main`.

---

## 12. Kit de UI moderno (estándar de diseño actual)

> **Cambio de prioridad (decisión del fundador, 2026-06-16):** la prioridad de
> diseño deja de ser gerontodiseño (CONSTITUTION Art. I) y pasa a **estándares
> modernos de UI/UX** (estilo Linear/GitHub). Las reglas de *correctness* siguen
> vigentes (sin overflow a 360dp, español sin voseo, máx 2 acciones en header),
> pero los objetivos táctiles gigantes / texto grande / subtítulos explicativos
> ya **no** son obligatorios. Módulos nuevos nacen con este kit; los existentes
> se migran al tocarlos.

**Kit reutilizable:** `lib/theme/app_ui.dart` (`AppUI` + `SoftCard`,
`InsetGroupedList`, `MinimalBadge`, `glassAppBar`). Módulo de referencia:
`CatalogOnlineHubScreen`.

**Reglas (Spec 062):**
1. Espaciado estricto en múltiplos de 8.
2. Tarjetas **blancas puras**, radius 12, sombra difusa `0 4 24 rgba(0,0,0,.04)`.
   Sin bordes pesados.
3. Separadores casi invisibles `#F1F5F9` o, mejor, whitespace.
4. Listas agrupadas (inset grouped): un contenedor, ítems con divisor hairline,
   sin caja por ítem.
5. Botones ghost (transparente + borde sutil) o solid neutro con un toque de
   color solo en el primario.
6. Badges pastel al 10%, sin borde, medium 12px.
7. Títulos SemiBold `#1E293B`; secundario 14px `#64748B`. Sin texto redundante.
8. Glassmorphism SOLO en barras (header/bottom): blur 15 + blanco 65%. El área
   de datos queda limpia y de alto contraste.
9. Densidad moderna, objetivos táctiles ~44dp. Íconos monocromos sutiles; nada
   de colores estridentes ni íconos enormes.

REGLA DE ORO al refactorizar visualmente: **no alterar lógica, navegación ni
estados** — solo presentación.
