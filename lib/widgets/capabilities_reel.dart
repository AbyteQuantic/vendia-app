// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// Reel horizontal animado en el Dashboard (spec §4.2) — muestra una
// card por cada capacidad opcional NO activada del tenant para que el
// dueño la descubra y la active de un toque. Cuando todas las
// capacidades opcionales están ON, el reel se OCULTA por completo
// (devuelve `SizedBox.shrink`, AC-07).
//
// Comportamiento:
//   - Auto-rotación cada ~3500ms (AC-04 — lento para tendero 50+).
//   - `viewportFraction` adaptativo: <600dp → 0.85 (card grande
//     mobile); ≥600dp → 0.4 (varias visibles en tablet/web).
//   - Pausa cuando el dueño toca/swipea (pan-down); reanuda 3s después
//     del último pan-end / pan-cancel (AC-08).
//   - Indicador de páginas (dots) grande (≥10dp) bajo el reel.
//
// Las cards muestran ícono + nombre + "Toca para activar". Tocar
// navega a `BusinessCapabilitiesScreen` con `highlightCapability`
// para que esa pantalla pulse el toggle correspondiente (AC-05).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/dashboard_modules.dart';
import '../screens/dashboard/business_capabilities_screen.dart';
import '../theme/app_theme.dart';
import '../utils/business_capability_map.dart';

/// Cadencia del autoplay — conservadora a propósito (Gerontodiseño,
/// AC-12). 3500ms da tiempo al tendero 50+ a leer una card antes de
/// que cambie.
const Duration _kAutoplayInterval = Duration(milliseconds: 3500);

/// Tiempo desde el último toque hasta que reanuda el autoplay (AC-08).
const Duration _kResumeDelay = Duration(seconds: 3);

class CapabilitiesReel extends StatefulWidget {
  /// Módulos opcionales del registro con su capacidad aún en OFF.
  ///
  /// El Dashboard los calcula con `unactivatedOptionalModules(flags)`
  /// y los pasa acá. Cuando la lista está vacía el reel se oculta.
  final List<DashboardModule> modules;

  /// Callback opcional disparado tras volver de
  /// `BusinessCapabilitiesScreen`. El Dashboard lo usa para refrescar
  /// los flags (la capacidad recién activada quita su card del reel).
  final VoidCallback? onReturned;

  const CapabilitiesReel({
    super.key,
    required this.modules,
    this.onReturned,
  });

  @override
  State<CapabilitiesReel> createState() => _CapabilitiesReelState();
}

class _CapabilitiesReelState extends State<CapabilitiesReel> {
  late final PageController _pageCtrl;
  Timer? _autoplayTimer;
  Timer? _resumeTimer;
  int _currentPage = 0;

  /// `viewportFraction` cacheado para crear/recrear el PageController
  /// cuando el ancho cruza el breakpoint de 600dp.
  double _viewportFraction = 0.85;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController(viewportFraction: _viewportFraction);
    // Arrancar autoplay tras el primer frame, así MediaQuery está
    // resuelto y no auto-rotamos sobre una lista de un solo elemento.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startAutoplay();
    });
  }

  @override
  void didUpdateWidget(covariant CapabilitiesReel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si la cantidad de módulos cambió (p. ej. el dueño activó uno y
    // volvió al Dashboard), reseteamos a la página 0 para que no
    // quede con un índice fuera de rango.
    if (widget.modules.length != oldWidget.modules.length) {
      _currentPage = 0;
      if (_pageCtrl.hasClients && widget.modules.isNotEmpty) {
        _pageCtrl.jumpToPage(0);
      }
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
    if (widget.modules.length <= 1) return;
    _autoplayTimer = Timer.periodic(_kAutoplayInterval, (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_currentPage + 1) % widget.modules.length;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
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

  /// Programa la reanudación 3s después del último toque (AC-08).
  void _scheduleResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_kResumeDelay, () {
      if (!mounted) return;
      _startAutoplay();
    });
  }

  Future<void> _openCapabilitiesScreen(DashboardModule module) async {
    HapticFeedback.lightImpact();
    _pauseAutoplay();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BusinessCapabilitiesScreen(
          highlightCapability: module.capability,
        ),
      ),
    );
    if (!mounted) return;
    widget.onReturned?.call();
    _startAutoplay();
  }

  /// Cards más altas en pantallas chicas (mobile) que en anchas
  /// (tablet/web). 360dp → 0.85 (card casi llena); ≥600dp → 0.4
  /// (~2.5 cards visibles).
  double _viewportFractionFor(double width) =>
      width < 600 ? 0.85 : 0.4;

  @override
  Widget build(BuildContext context) {
    if (widget.modules.isEmpty) {
      // AC-07: sin capacidades opcionales pendientes, el reel
      // se oculta por completo.
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final desired = _viewportFractionFor(width);
        // Re-crear el PageController si el viewportFraction cambió
        // (rotación, redimensionado de ventana web).
        if ((desired - _viewportFraction).abs() > 0.001) {
          _viewportFraction = desired;
          // No podemos modificar `viewportFraction` en caliente; lo
          // posponemos al próximo frame con un controller nuevo.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {});
          });
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  '✨ Descubrí más opciones para tu negocio',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                key: const Key('capabilities_reel_pageview'),
                height: 130,
                child: GestureDetector(
                  onPanDown: (_) => _pauseAutoplay(),
                  onPanEnd: (_) => _scheduleResume(),
                  onPanCancel: () => _scheduleResume(),
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: widget.modules.length,
                    onPageChanged: (p) {
                      if (!mounted) return;
                      setState(() => _currentPage = p);
                    },
                    itemBuilder: (context, index) {
                      final m = widget.modules[index];
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6),
                        child: _ReelCard(
                          module: m,
                          onTap: () => _openCapabilitiesScreen(m),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _DotsIndicator(
                count: widget.modules.length,
                current: _currentPage,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Una card del reel. Altura ≥120dp; texto ≥17pt; touch target grande.
class _ReelCard extends StatelessWidget {
  final DashboardModule module;
  final VoidCallback onTap;

  const _ReelCard({required this.module, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: Key('reel_card_${module.id}'),
      button: true,
      label: '${module.title}. Toca para activar.',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: module.color.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: module.color.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(module.icon, color: module.color, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toca para activar',
                      style: TextStyle(
                        fontSize: 14,
                        color: module.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicador de páginas (dots). Grande (10dp) para que el tendero 50+
/// vea claramente en qué card va el reel (AC-12).
class _DotsIndicator extends StatelessWidget {
  final int count;
  final int current;

  const _DotsIndicator({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == current;
        return Container(
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

/// Re-export para que los consumidores del reel no tengan que importar
/// `business_capability_map.dart` al sumar metadata.
typedef ReelCapability = OptionalCapability;
