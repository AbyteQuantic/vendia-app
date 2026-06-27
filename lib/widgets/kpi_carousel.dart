// Spec: specs/040-capacidades-fotos-config-card/spec.md
//
// Carrusel inmersivo de KPIs del Dashboard (Ventas hoy / Más
// vendido / Inventario y compañía). Reemplaza la fila de "glass cards"
// previas por cards a pantalla casi completa con foto representativa
// + valor grande, en el mismo estilo que `ActiveCapabilitiesSection`.
//
// El widget es puro: recibe la lista de [KpiCardData] desde el
// Dashboard y se redibuja cuando esa lista cambia. Los datos
// (totalToday, topProduct, prodCount) los arma el Dashboard a partir
// de su estado reactivo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'carousel_navigation.dart';

/// Datos para una card del carrusel de KPIs.
class KpiCardData {
  /// Título corto del KPI (ej. "Ventas de hoy").
  final String title;

  /// Valor grande a destacar (ej. "$120.000", "20 ref.", "Coca-Cola").
  final String value;

  /// Sub-valor opcional debajo del valor (ej. "5 ventas").
  final String? subtitle;

  /// URL de la foto representativa del concepto (Pexels — licencia libre).
  final String photoUrl;

  /// Ícono fallback si la foto no carga (offline / CDN cambia el ID).
  final IconData fallbackIcon;

  /// Color de acento del placeholder y del CTA circular.
  final Color accentColor;

  /// Callback al tocar la card. Suele navegar a la pantalla detallada.
  final VoidCallback onTap;

  /// Acción opcional para "quitar del inicio" (desactivar la capacidad).
  /// Solo la traen las cards de capacidades activas — los KPIs la dejan
  /// en null. Cuando está presente, la card muestra un botón "quitar" y
  /// responde al pulsado largo.
  final VoidCallback? onRemove;

  const KpiCardData({
    required this.title,
    required this.value,
    required this.photoUrl,
    required this.fallbackIcon,
    required this.accentColor,
    required this.onTap,
    this.subtitle,
    this.onRemove,
  });
}

const Duration _kAutoplayInterval = Duration(seconds: 20);
const Duration _kResumeDelay = Duration(seconds: 3);

class KpiCarousel extends StatefulWidget {
  final List<KpiCardData> cards;

  const KpiCarousel({super.key, required this.cards});

  @override
  State<KpiCarousel> createState() => _KpiCarouselState();
}

class _KpiCarouselState extends State<KpiCarousel> {
  late PageController _pageCtrl;
  Timer? _autoplayTimer;
  Timer? _resumeTimer;
  int _currentPage = 0;
  // 0.66 — más bajo que antes (0.70) para que asome MÁS de las cards
  // vecinas: así se nota de inmediato que hay más ítems a los lados y
  // el conjunto se ve más junto, no una card aislada en el centro.
  // 0.62: deja ver MÁS de las cards vecinas → se sienten más cercanas entre sí.
  final double _viewportFraction = 0.62;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: _viewportFraction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startAutoplay();
    });
  }

  @override
  void didUpdateWidget(covariant KpiCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cards.length != oldWidget.cards.length) {
      _currentPage = 0;
      if (_pageCtrl.hasClients) _pageCtrl.jumpToPage(0);
      _restartAutoplay();
    }
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _resumeTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _startAutoplay() {
    _autoplayTimer?.cancel();
    if (widget.cards.length <= 1) return;
    _autoplayTimer = Timer.periodic(_kAutoplayInterval, (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_currentPage + 1) % widget.cards.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
      );
    });
  }

  void _pauseAutoplay() {
    _autoplayTimer?.cancel();
    _resumeTimer?.cancel();
  }

  void _restartAutoplay() {
    _autoplayTimer?.cancel();
    _startAutoplay();
  }

  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_kResumeDelay, () {
      if (!mounted) return;
      _startAutoplay();
    });
  }

  /// Avanza/retrocede `delta` páginas con wrap-around (consistente con el
  /// autoplay). Lo usan las flechas de desktop (AC-02).
  void _goTo(int delta) {
    if (!_pageCtrl.hasClients || widget.cards.length <= 1) return;
    final n = widget.cards.length;
    _animateTo((_currentPage + delta + n) % n);
  }

  /// Salta directo a `index` — lo usan los dots tocables (AC-03).
  void _jumpTo(int index) {
    if (!_pageCtrl.hasClients || index < 0 || index >= widget.cards.length) {
      return;
    }
    _animateTo(index);
  }

  void _animateTo(int target) {
    _pauseAutoplay();
    _pageCtrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    _scheduleResume();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 340,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Flechas solo en pantallas anchas (desktop/web). En mobile
              // el swipe basta y estorbarían en 360dp (AC-04).
              final showArrows =
                  constraints.maxWidth >= kCarouselArrowsBreakpoint &&
                      widget.cards.length > 1;
              return Stack(
                children: [
                  GestureDetector(
                    onPanDown: (_) => _pauseAutoplay(),
                    onPanEnd: (_) => _scheduleResume(),
                    onPanCancel: () => _scheduleResume(),
                    // Habilita arrastre con mouse/trackpad (AC-01).
                    child: MouseDraggableScroll(
                      child: PageView.builder(
                        controller: _pageCtrl,
                        itemCount: widget.cards.length,
                        onPageChanged: (p) {
                          if (!mounted) return;
                          setState(() => _currentPage = p);
                        },
                        itemBuilder: (context, index) => _KpiCard(
                          data: widget.cards[index],
                          pageCtrl: _pageCtrl,
                          pageIndex: index,
                        ),
                      ),
                    ),
                  ),
                  if (showArrows) ...[
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: CarouselArrowButton(
                          isNext: false,
                          onTap: () => _goTo(-1),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: CarouselArrowButton(
                          isNext: true,
                          onTap: () => _goTo(1),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        CarouselDots(
          count: widget.cards.length,
          current: _currentPage,
          onTap: _jumpTo,
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final KpiCardData data;
  final PageController pageCtrl;
  final int pageIndex;

  const _KpiCard({
    required this.data,
    required this.pageCtrl,
    required this.pageIndex,
  });

  /// Signed distance — preserva el signo para que la rotación 3D sepa
  /// hacia qué lado inclinar la card (positivo = derecha, negativo =
  /// izquierda). Clamped a [-1, 1] para que más allá del primer vecino
  /// la rotación no se siga acumulando.
  double _signedDistance() {
    if (!pageCtrl.hasClients || pageCtrl.position.haveDimensions == false) {
      return pageIndex == 0 ? 0.0 : 1.0;
    }
    final page = pageCtrl.page ?? pageCtrl.initialPage.toDouble();
    return (page - pageIndex).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final accent = data.accentColor;
    // PERF: en vez de setState por frame del carrusel entero, cada card visible
    // se redibuja sola escuchando el PageController. El contenido (child) se
    // construye UNA vez; el builder solo recalcula escala/opacidad/rotación.
    return AnimatedBuilder(
      animation: pageCtrl,
      builder: (context, child) {
        final signed = _signedDistance();
        final d = signed.abs();
        final scale = 1.0 - (d * 0.10);
        final opacity = 1.0 - (d * 0.35);
        final rotationY = -signed * 0.55; // radianes (~31°) — más arco tipo aro
        final transform = Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..scaleByDouble(scale, scale, 1.0, 1.0)
          ..rotateY(rotationY);
        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: transform,
            child: child,
          ),
        );
      },
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                HapticFeedback.lightImpact();
                data.onTap();
              },
              onLongPress: data.onRemove == null
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      data.onRemove!();
                    },
              child: Container(
                // Tarjeta limpia: borde hairline 1px + UNA sombra muy
                // difuminada y amplia (blur 20, ~3%) — fuera las sombras
                // pesadas dobles que ensuciaban el carrusel.
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  // 0.05 explícito (ronda 1): sobre página blanca el token
                  // compartido (0.02) dejaría la card sin contorno visible.
                  border: Border.all(color: const Color(0x0D000000), width: 1),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  // -1 para que la imagen no se asome por fuera del borde 1px.
                  borderRadius: BorderRadius.circular(23),
                  // Estructura "opción 3": imagen a sangre completa con una
                  // etiqueta glass abajo (título + valor). El coverflow sigue
                  // siendo horizontal.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(color: accent.withValues(alpha: 0.18)),
                      Image.network(
                        data.photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _placeholder(accent, data.fallbackIcon),
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return _placeholder(accent, data.fallbackIcon);
                        },
                      ),
                      // Scrim inferior (decorativo → ignora toques) para que el
                      // texto se lea sobre la foto.
                      const Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.center,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Color(0x99000000)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Etiqueta glass inferior (estructura "opción 3"): título,
                      // valor/estado y subtítulo (si viene). IgnorePointer para
                      // que el toque caiga en el InkWell de la card (abre).
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.42),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  data.title,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                if (data.onRemove != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_rounded,
                                          size: 14, color: Color(0xFF34D399)),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          data.value,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    data.value,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      height: 1.0,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                if (data.subtitle != null) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    data.subtitle!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white70,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Botón "quitar del inicio" — ÚLTIMO (encima de todo) y
                      // tappable. Solo en capacidades activas.
                      if (data.onRemove != null)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.45),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                data.onRemove!();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(7),
                                child: Icon(Icons.close_rounded,
                                    size: 18, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
  }

  Widget _placeholder(Color accent, IconData icon) {
    return Container(
      color: accent.withValues(alpha: 0.18),
      child: Center(
        child: Icon(icon, size: 84, color: accent.withValues(alpha: 0.7)),
      ),
    );
  }
}
