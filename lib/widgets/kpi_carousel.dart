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
import 'dashboard_ui_kit.dart';

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
  final double _viewportFraction = 0.66;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: _viewportFraction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pageCtrl.addListener(_onPageScroll);
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
    _pageCtrl.removeListener(_onPageScroll);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _onPageScroll() {
    if (mounted) setState(() {});
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
    final signed = _signedDistance();
    final d = signed.abs();
    // 1.0 (centro) → 0.90 (lateral). Menos encogido que antes (0.82)
    // para que las cards vecinas se vean cercanas y claras, no lejanas.
    final scale = 1.0 - (d * 0.10);
    // 1.0 (centro) → 0.65 (lateral). Antes 0.45 — subo la opacidad para
    // que el vecino se identifique a simple vista.
    final opacity = 1.0 - (d * 0.35);
    // Rotación Y más suave (~24°) — el coverflow se mantiene pero sin
    // alejar tanto las cards laterales.
    final rotationY = -signed * 0.42; // radianes (~24°)

    // Matrix4 con perspectiva — `setEntry(3, 2, 0.0014)` es el valor
    // típico para perspectiva agradable en flutter; sin este entry la
    // rotateY se ve plana (escalado afín, no 3D).
    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.0014)
      ..scaleByDouble(scale, scale, 1.0, 1.0)
      ..rotateY(rotationY);

    return Opacity(
      opacity: opacity,
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03 * opacity),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  // -1 para que la imagen no se asome por fuera del borde 1px.
                  borderRadius: BorderRadius.circular(23),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Foto arriba (proporción póster — domina) ────
                      Expanded(
                        flex: 5,
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
                            // Botón "quitar del inicio" — solo en capacidades
                            // activas. Desactiva la capacidad y la regresa al
                            // listado de "Descubre más opciones".
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
                      // ── Bloque blanco inferior con info estructurada ─
                      Expanded(
                        flex: 4,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Título + subtitle (zona "destino" /
                              // "ubicación" del estilo de referencia).
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    data.title,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: DashUI.ink,
                                      height: 1.15,
                                      letterSpacing: -0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (data.subtitle != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.fiber_manual_record,
                                            size: 8,
                                            color: accent.withValues(alpha: 0.8)),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            data.subtitle!,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: DashUI.inkSoft,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              // Zona inferior. Para KPIs: valor grande.
                              // Para capacidades activas (onRemove != null):
                              // el estado ("Activo") es un badge semántico
                              // pequeño y alineado — no un texto suelto
                              // gigante compitiendo con el título.
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: data.onRemove != null
                                        ? Align(
                                            alignment: Alignment.centerLeft,
                                            child: DashStatusBadge(
                                              label: data.value,
                                              color: const Color(0xFF059669),
                                            ),
                                          )
                                        : Text(
                                            data.value,
                                            style: TextStyle(
                                              fontSize: 28,
                                              fontWeight: FontWeight.w900,
                                              color: accent,
                                              height: 1.0,
                                              letterSpacing: -0.5,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Material(
                                    color: accent,
                                    shape: const CircleBorder(),
                                    elevation: 0,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        data.onTap();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(14),
                                        child: Icon(
                                          Icons.arrow_forward_rounded,
                                          color: Colors.white,
                                          size: 26,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
