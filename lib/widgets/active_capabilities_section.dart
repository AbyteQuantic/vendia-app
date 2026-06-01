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
  final double _viewportFraction = 0.78;

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
            height: 300,
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

  /// Distancia 0.0 (centrada) → 1.0+ (totalmente fuera). Se calcula a
  /// partir de `pageCtrl.page` para una transición fluida durante
  /// el swipe.
  double _distanceFromCenter() {
    if (!pageCtrl.hasClients || pageCtrl.position.haveDimensions == false) {
      return pageIndex == 0 ? 0.0 : 1.0;
    }
    final page = pageCtrl.page ?? pageCtrl.initialPage.toDouble();
    return (page - pageIndex).abs().clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor();
    final fallback = _fallbackIcon();
    final photoUrl = _photoUrl();
    final d = _distanceFromCenter();
    // 1.0 (centro) → 0.92 (lateral). Lerp suave.
    final scale = 1.0 - (d * 0.08);
    // 1.0 (centro) → 0.6 (lateral).
    final opacity = 1.0 - (d * 0.4);

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 0),
      child: Opacity(
        opacity: opacity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Material(
            elevation: 0,
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _openModule(context),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25 * opacity),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Foto de fondo.
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
                      // Gradient inferior para legibilidad del texto.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.0),
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.75),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // ⚙️ chip arriba-derecha.
                      Positioned(
                        top: 14,
                        right: 14,
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: const CircleBorder(),
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
                      // Bloque inferior: título + subtítulo + CTA circular.
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 20,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    module.title,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      height: 1.1,
                                      shadows: [
                                        Shadow(
                                            blurRadius: 8,
                                            color: Colors.black54,
                                            offset: Offset(0, 2)),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    module.subtitle,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white
                                          .withValues(alpha: 0.92),
                                      fontWeight: FontWeight.w500,
                                      height: 1.3,
                                      shadows: const [
                                        Shadow(
                                            blurRadius: 6,
                                            color: Colors.black45,
                                            offset: Offset(0, 1)),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // CTA principal: botón circular grande con
                            // play-style. Tooltip largo para tendero
                            // 50+.
                            Tooltip(
                              message: _ctaLabel(),
                              child: Material(
                                color: Colors.white,
                                shape: const CircleBorder(),
                                elevation: 4,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () => _openModule(context),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Icon(
                                      Icons.arrow_forward_rounded,
                                      color: accent,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
