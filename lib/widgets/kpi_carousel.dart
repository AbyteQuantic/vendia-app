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

import '../theme/app_theme.dart';

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

  const KpiCardData({
    required this.title,
    required this.value,
    required this.photoUrl,
    required this.fallbackIcon,
    required this.accentColor,
    required this.onTap,
    this.subtitle,
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
  // 0.70 — las cards laterales se superponen ligeramente con la
  // central, lo que sumado a la rotación Y crea el efecto coverflow
  // semicircular pedido por el dueño.
  final double _viewportFraction = 0.70;

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

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 340,
          child: GestureDetector(
            onPanDown: (_) => _pauseAutoplay(),
            onPanEnd: (_) => _scheduleResume(),
            onPanCancel: () => _scheduleResume(),
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
        const SizedBox(height: 12),
        _DotsIndicator(
          count: widget.cards.length,
          current: _currentPage,
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
    // 1.0 (centro) → 0.82 (lateral). Bajo más la escala para
    // reforzar el efecto de profundidad del coverflow 3D.
    final scale = 1.0 - (d * 0.18);
    // 1.0 (centro) → 0.45 (lateral). Las laterales quedan "atrás".
    final opacity = 1.0 - (d * 0.55);
    // Rotación Y máxima ~30° hacia el centro. signed > 0 (la card está
    // a la derecha del scroll) gira a la izquierda — y viceversa — para
    // dar la sensación de un semicírculo enfrentándose al usuario.
    final rotationY = -signed * 0.55; // radianes (~31°)

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
              borderRadius: BorderRadius.circular(28),
              onTap: () {
                HapticFeedback.lightImpact();
                data.onTap();
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15 * opacity),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12 * opacity),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
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
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
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
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textSecondary,
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
                              // Valor grande + botón circular (zona
                              // "precio + play" del estilo de
                              // referencia).
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Text(
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
                                    elevation: 6,
                                    shadowColor:
                                        accent.withValues(alpha: 0.5),
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

class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : AppTheme.borderColor,
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}
