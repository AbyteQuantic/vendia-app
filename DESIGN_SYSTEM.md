# VendIA — Design System (REGLA DE ORO)

> **Fuente única de verdad** del aspecto de la app. Cualquier agente (humano o IA)
> que cree o ajuste UI en `lib/screens/**` o `lib/widgets/**` DEBE leer este
> archivo + [`UI_RULES.md`](UI_RULES.md) ANTES de escribir, y aplicarlo. Si una
> pantalla no cumple, no está terminada.

## 🏆 REGLA DE ORO (HARD — no negociable)

1. **Un solo origen de tokens.** Colores, tipografía, espaciado, radios y sombras
   viven SOLO en `lib/theme/app_theme.dart` (tema Material) y
   `lib/theme/app_ui.dart` (kit `AppUI`). **Prohibido** hardcodear `Color(0x..)`,
   tamaños de fuente sueltos o `EdgeInsets` mágicos en pantallas: use los tokens.
2. **Componentes del kit, no widgets crudos.** Use `AppButton`, `SoftCard`,
   `InsetGroupedList`, `glassAppBar`, `MinimalBadge`, `GhostButton`. **Nunca**
   `ElevatedButton`/`OutlinedButton` crudos en pantallas — su theme legacy (22px /
   64dp) parte el texto en 360dp. (Causa del bug del modal de voz, 2026-06-27.)
3. **Cero overflow y cero texto partido a 360dp.** Los botones llevan label de
   UNA línea con ellipsis. Etiquetas cortas; el detalle va en texto de apoyo, no
   dentro del botón. Probar mentalmente a 360dp.
4. **Marca consistente.** El color de acción es `AppTheme.primary` (azul de
   marca); el logo y la tipografía de marca son los oficiales (§Marca). Nada de
   púrpuras/índigos sueltos por pantalla.
5. **Copy en español, modo USTED**, sobrio (ver UI_RULES §11).

Antes de dar por terminada una pantalla, pase el **checklist** del final.

---

## Marca (identidad unificada VendIA)

Logo: marca **VendIA** (check que se vuelve flecha ascendente, en azul→cyan).
Tagline: *"POS móvil y herramientas para emprendedores"*.

**Componentes de logo** (`lib/widgets/vendia_logo.dart`, NO imágenes):
- `VendiaWordmark` — «Vend» + «**IA**» (IA en cyan de marca, mayúscula).
- `VendiaMark` — cuadrado redondeado con el check/flecha en gradiente azul→cyan.
- `VendiaLogo` — marca + wordmark en fila (headers/onboarding).

### Paleta azul-cyan (aplicada en `app_theme.dart`)
| Rol | Token | Hex |
|-----|-------|-----|
| Azul de marca (acción) | `AppTheme.primary` | `#0E6BA8` |
| Azul profundo / ink | `AppTheme.primaryDark` | `#0A2540` |
| Cyan de acento (la «IA») | `AppTheme.accent` | `#22C3E6` |
| Cyan claro (fondos suaves) | `AppTheme.accentSoft` | `#E6F7FB` |
| Éxito / Error / Aviso | success/error/warning | se conservan |

> Base afinable con el fundador viendo la app; cualquier ajuste va SOLO en
> `app_theme.dart` (un único lugar).

### Tipografía de marca: **Inter** (= equivalente libre a la fuente de Apple, SF Pro)
Apple usa San Francisco (propietaria, no empaquetable fuera de iOS). Usamos
**Inter** (OFL), diseñada como equivalente directo de SF: idéntica en estilo y
consistente en iOS/Android/web. Empaquetada en `assets/fonts/` (400/500/600/700)
y declarada en `pubspec.yaml`; `fontFamily: 'Inter'` se fija SOLO en
`app_theme.dart`. Las TextStyle del kit heredan esta familia.

---

## Tokens (kit `AppUI` — `lib/theme/app_ui.dart`)

- **Espaciado (escala 8):** `s4 s8 s12 s16 s24`. Nada de números mágicos.
- **Radios:** `radius = 12` (tarjetas), `radiusSm = 6` (densidad pro).
- **Color/tipo:** `ink` (#1E293B títulos), `inkSoft` (#64748B secundario),
  `hairline` (divisor), `pageBg` (fondo), `border` (1px sobrio).
- **Texto:** `title` (18 w600), `sectionLabel` (13 w600), `bodyStrong` (16 w600),
  `bodySoft` (14), `tabular`/`tabularStrong` (cifras).
- **Sombra:** `AppUI.shadow` (difusa ~4%, nunca sombras pesadas).

## Componentes
- **`AppButton(label, onPressed, {icon, variant: primary|secondary|danger})`** —
  botón estándar (alto 50, radio 12, 16px, una línea). **Úselo siempre.**
- **`SoftCard`** — tarjeta blanca con sombra difusa.
- **`InsetGroupedList`** — lista agrupada (un contenedor, divisor hairline).
- **`glassAppBar(title, {onBack, actions})`** — header con blur.
- **`MinimalBadge`**, **`GhostButton`**, **`GlassCard`**.

## Patrón de modal/bottom-sheet
- Fondo blanco, esquinas `Radius.circular(20)` arriba, manija (handle) centrada.
- Contenido en `SingleChildScrollView` dentro de `Flexible` (no overflow al teclado).
- Acciones al pie: **1 primaria** `AppButton(primary)` ancha + a lo sumo 1
  `AppButton(secondary)` + acciones terciarias como `TextButton` cortos.
- Acciones destructivas/finales (vaciar, cobrar, eliminar) SIEMPRE confirman.

## Checklist (antes de terminar una pantalla)
- [ ] Sin `Color(0x..)` ni fontSize/EdgeInsets mágicos — solo tokens `AppUI`/tema.
- [ ] Botones = `AppButton` (no Elevated/Outlined crudos); label 1 línea.
- [ ] Sin overflow ni texto partido a 360dp.
- [ ] Tarjetas/listas = `SoftCard`/`InsetGroupedList`; headers = `glassAppBar`.
- [ ] Color de acción = `AppTheme.primary` (marca); sin colores sueltos.
- [ ] Copy español USTED, sobrio.
- [ ] `flutter analyze` limpio + el módulo probado.
