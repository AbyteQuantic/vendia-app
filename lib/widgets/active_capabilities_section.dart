// Spec: specs/040-capacidades-fotos-config-card/spec.md
//
// Carrusel del Dashboard con las capacidades opcionales ACTIVAS, cada
// una con foto real grande (Pexels — registry F040). Estilo:
//
//   - PageView horizontal con viewportFraction 0.78 → la card central
//     casi llena el ancho, las laterales asoman lo suficiente para
//     anunciar "hay más".
//   - Foto cubre la mayor parte de la card; gradient overlay inferior
//     para legibilidad del título.
//   - Botón circular grande inferior-derecha: acción principal (abrir
//     módulo funcional, p. ej. "Ver mis cotizaciones").
//   - Chip ⚙️ superior-derecha: abre la pantalla dedicada de la
//     capacidad (settings + activación).
//   - Animación de escala (1.0 centro / 0.9 laterales) + opacidad
//     (1.0 centro / 0.65 laterales) basada en la distancia de página.
//   - Auto-rotación cada 20s (pidió el dueño). Pausa al tocar; reanuda
//     3s después del último pan-end / pan-cancel.
//   - Dots indicador grandes (10dp / activo 22dp) — Art. I.
//
// Si NO hay capacidades opcionales activas, retorna `SizedBox.shrink`
// — la sección no aparece en el Dashboard de un tenant nuevo.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/dashboard_modules.dart';
import '../screens/capabilities/capabilities_registry.dart';
import '../screens/capabilities/capability_scaffold.dart';
import '../screens/quotes/quote_capability_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/business_capability_map.dart';

/// Cadencia de auto-rotación — 20s (pedida por el dueño).
const Duration _kAutoplayInterval = Duration(seconds: 20);

/// Tiempo desde el último toque hasta que reanuda la auto-rotación.
const Duration _kResumeDelay = Duration(seconds: 3);

class ActiveCapabilitiesSection extends StatefulWidget {
  final FeatureFlags flags;

  /// Refrescar el Dashboard tras volver de la pantalla de capacidad
  /// (p. ej. si el dueño la apagó).
  final VoidCallback? onReturned;

  const ActiveCapabilitiesSection({
    super.key,
    required this.flags,
    this.onReturned,
  });

  @override
  State<ActiveCapabilitiesSection> createState() =>
      _ActiveCapabilitiesSectionState();
}

class _ActiveCapabilitiesSectionState extends State<ActiveCapabilitiesSection> {
  late PageController _pageCtrl;
  Timer? _autoplayTimer;
  Timer? _resumeTimer;
  int _currentPage = 0;
  // 0.70 — las laterales se superponen ligeramente con la central,
  // lo que sumado a la rotación 3D crea el efecto coverflow
  // semicircular pedido por el dueño.
  final double _viewportFraction = 0.70;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: _viewportFraction);
    // initial-page = 0; el primer frame lo confirma.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Listener para repintar las cards laterales con scale/opacity
      // mientras el dueño hace swipe.
      _pageCtrl.addListener(_onPageScroll);
      _startAutoplay();
    });
  }

  @override
  void didUpdateWidget(covariant ActiveCapabilitiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si cambia el set de activas, reiniciamos a la primera.
    if (_activeModules(oldWidget.flags).length !=
        _activeModules(widget.flags).length) {
      _currentPage = 0;
      if (_pageCtrl.hasClients) {
        _pageCtrl.jumpToPage(0);
      }
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
    // Trigger rebuild para que las cards apliquen scale/opacity nuevos.
    if (mounted) setState(() {});
  }

  List<DashboardModule> _activeModules(FeatureFlags flags) {
    return dashboardModules
        .where((m) =>
            m.layer == ModuleLayer.optional &&
            capabilityEnabled(m.capability, flags) &&
            (m.capability == OptionalCapability.quotes ||
                capabilitiesRegistry.containsKey(m.capability)))
        .toList();
  }

  void _startAutoplay() {
    _autoplayTimer?.cancel();
    final modules = _activeModules(widget.flags);
    if (modules.length <= 1) return;
    _autoplayTimer = Timer.periodic(_kAutoplayInterval, (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_currentPage + 1) % modules.length;
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
    final modules = _activeModules(widget.flags);
    if (modules.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Text(
              '⚡ Sus capacidades activas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          SizedBox(
            height: 360,
            child: GestureDetector(
              onPanDown: (_) => _pauseAutoplay(),
              onPanEnd: (_) => _scheduleResume(),
              onPanCancel: () => _scheduleResume(),
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: modules.length,
                onPageChanged: (p) {
                  if (!mounted) return;
                  setState(() => _currentPage = p);
                },
                itemBuilder: (context, index) {
                  return _CarouselCard(
                    module: modules[index],
                    pageCtrl: _pageCtrl,
                    pageIndex: index,
                    onReturned: () {
                      widget.onReturned?.call();
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          _DotsIndicator(
            count: modules.length,
            current: _currentPage,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// Card individual del carrusel. Reactiva al scroll del PageController
/// para aplicar scale/opacity a medida que se centra o se aleja.
class _CarouselCard extends StatelessWidget {
  final DashboardModule module;
  final PageController pageCtrl;
  final int pageIndex;
  final VoidCallback onReturned;

  const _CarouselCard({
    required this.module,
    required this.pageCtrl,
    required this.pageIndex,
    required this.onReturned,
  });

  Widget _capabilityScreen() {
    if (module.capability == OptionalCapability.quotes) {
      return const QuoteCapabilityScreen();
    }
    final meta = capabilitiesRegistry[module.capability]!;
    return CapabilityScaffold(metadata: meta);
  }

  String _photoUrl() {
    if (module.capability == OptionalCapability.quotes) {
      return 'https://images.pexels.com/photos/95916/pexels-photo-95916.jpeg?auto=compress&cs=tinysrgb&w=900&h=700&fit=crop';
    }
    return capabilitiesRegistry[module.capability]?.heroPhotoUrl ?? '';
  }

  IconData _fallbackIcon() {
    if (module.capability == OptionalCapability.quotes) {
      return Icons.description_outlined;
    }
    return capabilitiesRegistry[module.capability]?.fallbackIcon ??
        module.icon;
  }

  Color _accentColor() {
    if (module.capability == OptionalCapability.quotes) {
      return const Color(0xFF1A2FA0);
    }
    return capabilitiesRegistry[module.capability]?.accentColor ??
        module.color;
  }

  String _ctaLabel() {
    return 'Abrir ${module.title.toLowerCase()}';
  }

  Future<void> _openModule(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => module.destination()),
    );
    onReturned();
  }

  Future<void> _openSettings(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _capabilityScreen()),
    );
    onReturned();
  }

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
    final accent = _accentColor();
    final fallback = _fallbackIcon();
    final photoUrl = _photoUrl();
    final signed = _signedDistance();
    final d = signed.abs();
    final scale = 1.0 - (d * 0.18);
    final opacity = 1.0 - (d * 0.55);
    // ~31° de rotación Y máxima — las laterales se inclinan hacia el
    // centro para dar el efecto semicircular.
    final rotationY = -signed * 0.55;

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
              onTap: () => _openModule(context),
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
                      // ── Foto arriba (póster) con ⚙️ overlay ─────────
                      Expanded(
                        flex: 5,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(color: accent.withValues(alpha: 0.18)),
                            if (photoUrl.isNotEmpty)
                              Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _placeholder(accent, fallback),
                                loadingBuilder: (_, child, progress) {
                                  if (progress == null) return child;
                                  return _placeholder(accent, fallback);
                                },
                              )
                            else
                              _placeholder(accent, fallback),
                            // Chip ⚙️ arriba-derecha (overlay sobre la
                            // foto). Único elemento que vive en la zona
                            // de la foto — el resto del contenido baja
                            // a la zona blanca.
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Material(
                                color: Colors.white.withValues(alpha: 0.96),
                                shape: const CircleBorder(),
                                elevation: 2,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _openSettings(context),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Icon(Icons.settings_rounded,
                                        color: accent, size: 20),
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    module.title,
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
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.fiber_manual_record,
                                          size: 8,
                                          color: accent.withValues(alpha: 0.8)),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          module.subtitle,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textSecondary,
                                            height: 1.35,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              // CTA grande: badge "ACTIVO" + botón
                              // circular abrir módulo.
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle_rounded,
                                              size: 14, color: accent),
                                          const SizedBox(width: 4),
                                          Text(
                                            'ACTIVO',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w900,
                                              color: accent,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Tooltip(
                                    message: _ctaLabel(),
                                    child: Material(
                                      color: accent,
                                      shape: const CircleBorder(),
                                      elevation: 6,
                                      shadowColor:
                                          accent.withValues(alpha: 0.5),
                                      child: InkWell(
                                        customBorder: const CircleBorder(),
                                        onTap: () => _openModule(context),
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

/// Dots indicador. 10dp inactivo / 22dp activo (Art. I).
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
