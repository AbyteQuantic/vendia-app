---
version: alpha
name: VendIA
description: >
  POS móvil offline-first para tiendas de barrio en Colombia. Audiencia primaria:
  adultos 50+ operando en celulares Android de gama media-baja. Las decisiones
  visuales priorizan contraste, áreas de toque grandes y tipografía sobredimensionada
  por encima de la densidad informativa.
colors:
  primary: "#1A2FA0"
  primary-light: "#3D5AFE"
  primary-dark: "#0D1B6F"
  background: "#FFFBF7"
  surface: "#F3F0EC"
  text-primary: "#1A1A1A"
  text-secondary: "#3D3D3D"
  border: "#D6D0C8"
  success: "#0D9668"
  warning: "#D97706"
  error: "#DC2626"
  on-primary: "#FFFFFF"
typography:
  display-lg:
    fontFamily: Roboto
    fontSize: 38px
    fontWeight: 700
    letterSpacing: -0.5px
  headline-md:
    fontFamily: Roboto
    fontSize: 30px
    fontWeight: 700
  title-lg:
    fontFamily: Roboto
    fontSize: 24px
    fontWeight: 600
  label-lg:
    fontFamily: Roboto
    fontSize: 22px
    fontWeight: 600
    letterSpacing: 0.3px
  body-lg:
    fontFamily: Roboto
    fontSize: 20px
    lineHeight: 1.5
  body-md:
    fontFamily: Roboto
    fontSize: 18px
    lineHeight: 1.5
rounded:
  sm: 16px
  md: 20px
  lg: 24px
  xl: 28px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  "2xl": 48px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    typography: "{typography.label-lg}"
    rounded: "{rounded.md}"
    height: 64px
    padding: 20px
  button-outlined:
    textColor: "{colors.primary}"
    rounded: "{rounded.md}"
    height: 64px
    padding: 20px
  input-field:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.sm}"
    padding: 20px
    typography: "{typography.body-md}"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    padding: 20px
  dialog:
    backgroundColor: "{colors.background}"
    rounded: "{rounded.xl}"
    padding: 24px
  fab:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.md}"
  snackbar:
    rounded: "{rounded.sm}"
    typography: "{typography.body-lg}"
---

## Overview

**Gerontodiseño** — la app la usa un tendero de 50+ años en un Android de gama
baja con la pantalla rayada y los lentes de leer puestos. Cada decisión visual
sirve a esa persona: contraste alto, tipografía mínima de 18px, tap-targets
mínimos de 60×60, lenguaje en español plano y sin jerga técnica.

El estilo es cálido y honesto — no buscamos parecer "fintech moderna". Buscamos
parecer una libreta de tendero confiable, con el respaldo silencioso de una
plataforma seria.

## Colors

Paleta de tres capas: índigo profundo para acción, beige cálido para descanso,
y un trío de estado (verde / ámbar / rojo) reservado para feedback transaccional.

- **Primary `#1A2FA0`** — índigo profundo. Único conductor de acción primaria
  (botones, FAB, links, foco de inputs). NO usar para texto corrido ni iconos
  decorativos.
- **Primary-light `#3D5AFE`** — sólo para variantes activas (chip seleccionado,
  hover) y badges informativos.
- **Background `#FFFBF7`** — blanco cálido tipo "papel reciclado". Reduce fatiga
  visual frente al `#FFFFFF` puro y diferencia la app de superficies de chat.
- **Surface `#F3F0EC`** — capa elevada (cards, inputs, chips). Crea profundidad
  sin sombras pesadas.
- **Text-primary `#1A1A1A`** — para titulares y datos críticos (precio, total).
- **Text-secondary `#3D3D3D`** — para metadatos, labels, fechas. NUNCA bajar
  contraste por debajo de WCAG AA (4.5:1) sobre `background`.
- **Success `#0D9668`** — verde "venta cerrada", "tienda abierta", "pago
  confirmado". No usar para informativo neutro.
- **Warning `#D97706`** — ámbar "fiar", "vence pronto", "stock bajo". Color
  semántico exclusivo para advertencias de negocio.
- **Error `#DC2626`** — rojo crítico. Botón de cerrar sesión, eliminar, error
  de pago. Una pantalla nunca debe tener más de un elemento en este color.

## Typography

Una sola familia: **Roboto**. Razón: se renderiza nativamente en EMUI/MIUI
(Android Huawei/Xiaomi, donde están la mayoría de los tenderos) sin caer al
fallback del sistema. Cualquier otra fuente acaba siendo Liberation Sans
en algún celular y rompe la consistencia.

**Regla mínima absoluta: ningún texto baja de 18px.** Esta regla supera a
cualquier otra consideración de jerarquía visual.

| Token | Tamaño | Uso |
|---|---|---|
| display-lg | 38px / 700 | Saludo principal del dashboard, "Bienvenido" en login |
| headline-md | 30px / 700 | Nombre del propietario, total a cobrar |
| title-lg | 24px / 600 | AppBar titles, sección headers |
| label-lg | 22px / 600 | Botones de acción, etiquetas grandes |
| body-lg | 20px | Texto de cuerpo principal, listas |
| body-md | 18px | Mínimo absoluto. Metadatos, captions, help text |

## Layout

**Spacing scale múltiplo de 4** — alineación vertical limpia y predecible:

```
xs  4px    inset entre ícono y texto adyacente
sm  8px    separación entre chips de fila
md  16px   padding interno de cards, gap vertical en formularios
lg  24px   margen lateral de pantalla (estándar)
xl  32px   bloque entre secciones del dashboard
2xl 48px   espacio "respira" entre header y primer card
```

**Margen lateral de pantalla = 20px** (no 24px). Aprovecha pantallas de 360dp
sin rebanar contenido.

**Áreas de toque mínimas**: 60×60dp para botones secundarios; 64dp de altura
para botones primarios. Más grande que Material guidelines (48dp) porque la
audiencia tiene dedos gruesos y motricidad fina disminuida.

## Shapes

`rounded.md` (20px) es el radio por defecto para CUALQUIER cosa interactiva
(botones, chips). `rounded.lg` (24px) para superficies pasivas (cards). El
radio xl (28px) se reserva para diálogos modales — la diferencia comunica
"esto interrumpe tu flujo, presta atención".

Shapes con esquinas vivas (radio 0) prohibidas excepto en separators horizontales.

## Components

### button-primary
Acción dominante de la pantalla. Una pantalla = un solo button-primary. Si
hay dos acciones competitivas, una debe ser `button-outlined`.

### input-field
Fondo `surface` (no `background`) para que se distinga visualmente del scaffold.
Borde 2.5px en estado focused — más grueso que Material guideline porque la
audiencia frecuentemente no detecta el cambio de color del borde delgado.

### card
Padding interno 20px. Nunca anidar cards (card dentro de card) — usa
divisores horizontales con border `#D6D0C8`.

### snackbar
`floating`, 16px de radio, dismiss horizontal. Mensajes en español plano,
máximo 80 caracteres. Toda acción asociada usa `actionTextColor` blanco
sobre fondo del color semántico del mensaje.

## Do's and Don'ts

**DO**
- Usa el primary (`#1A2FA0`) sólo para 1 acción dominante por pantalla.
- Pinta los estados de error / warning / success exclusivamente con su color semántico.
- Mantén todo texto ≥18px, incluso captions.
- Respeta el margen lateral de 20px en TODA pantalla.

**DON'T**
- No introduzcas colores fuera de la paleta. Si un nuevo módulo "necesita" un
  color, debate primero — probablemente es un mal-uso de un color existente.
- No uses fontWeight: 400 (regular) para títulos. Mínimo 600.
- No degradas contraste por estética. WCAG AA es piso, no techo.
- No uses sombras pesadas (`elevation > 4`). La profundidad la da el surface,
  no el shadow.
