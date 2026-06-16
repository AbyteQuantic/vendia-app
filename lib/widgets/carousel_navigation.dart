// Spec: specs/054-carrusel-navegacion-desktop/spec.md
//
// Controles de navegación compartidos por los carruseles del Dashboard
// (`KpiCarousel` y `CapabilitiesReel`). Resuelven el bug de desktop/web:
// `PageView` solo acepta gestos touch/pen por defecto, así que con el
// mouse no se podía navegar ni había flechas o dots tocables.
//
//   - [CarouselScrollBehavior] / [MouseDraggableScroll]: habilitan el
//     arrastre con mouse y trackpad (AC-01).
//   - [CarouselArrowButton]: flecha circular prev/siguiente, objetivo
//     táctil 44dp, solo en pantallas anchas (AC-02 / AC-04).
//   - [CarouselDots]: indicador de páginas con dots tocables y objetivo
//     táctil ≥44dp (AC-03), reemplaza los dots privados de cada widget.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ancho (dp) a partir del cual los carruseles muestran flechas
/// prev/siguiente. Por debajo (mobile 360dp) el swipe táctil basta y las
/// flechas estorbarían (AC-04).
const double kCarouselArrowsBreakpoint = 600;

/// `ScrollBehavior` que permite arrastrar scrollables (PageView) con
/// mouse y trackpad además de touch. El default de Flutter excluye el
/// mouse, por eso en web/desktop el carrusel no respondía al arrastre.
class CarouselScrollBehavior extends MaterialScrollBehavior {
  const CarouselScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  // CRÍTICO: este behavior REEMPLAZA al global de la app dentro del
  // carrusel. El global (main.dart) ya desactiva el glow de overscroll
  // y en web Material muestra scrollbar por defecto. Sin reproducir eso
  // acá, el PageView en web reaparecía con scrollbar + glow (el "se dañó
  // en mobile"). Los anulamos para igualar la config global.
  @override
  Widget buildScrollbar(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}

/// Envuelve un scrollable (típicamente un `PageView`) para que acepte
/// arrastre con mouse/trackpad (AC-01).
class MouseDraggableScroll extends StatelessWidget {
  final Widget child;

  const MouseDraggableScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: const CarouselScrollBehavior(),
        child: child,
      );
}

/// Flecha circular prev/siguiente superpuesta al costado de un carrusel.
/// Objetivo táctil 44dp (gerontodiseño). Se muestra solo en layouts
/// anchos — el carrusel decide cuándo según [kCarouselArrowsBreakpoint].
class CarouselArrowButton extends StatelessWidget {
  /// `true` → flecha derecha (siguiente); `false` → izquierda (anterior).
  final bool isNext;
  final VoidCallback onTap;

  const CarouselArrowButton({
    super.key,
    required this.isNext,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isNext ? 'Siguiente' : 'Anterior',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              isNext
                  ? Icons.chevron_right_rounded
                  : Icons.chevron_left_rounded,
              color: AppTheme.primary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

/// Indicador de páginas (dots). Los dots son tocables (AC-03): tocar uno
/// salta a esa página vía [onTap]. El objetivo táctil es ≥44dp de alto
/// aunque el dot visual sea pequeño (gerontodiseño). Si [onTap] es null
/// los dots quedan decorativos.
class CarouselDots extends StatelessWidget {
  final int count;
  final int current;
  final ValueChanged<int>? onTap;
  final Color? activeColor;
  final Color? inactiveColor;

  const CarouselDots({
    super.key,
    required this.count,
    required this.current,
    this.onTap,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    final active = activeColor ?? AppTheme.primary;
    final inactive = inactiveColor ?? AppTheme.borderColor;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == current;
        final dot = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: isActive ? 22 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: isActive ? active : inactive,
            borderRadius: BorderRadius.circular(5),
          ),
        );
        return Semantics(
          button: onTap != null,
          label: 'Ir a la página ${i + 1}',
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(i),
            customBorder: const StadiumBorder(),
            // 10dp (dot) + 17*2 = 44dp de alto → objetivo táctil cómodo
            // sin desplazar mucho el layout vertical.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 17),
              child: dot,
            ),
          ),
        );
      }),
    );
  }
}
