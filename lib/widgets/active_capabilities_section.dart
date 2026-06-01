// Spec: specs/040-capacidades-fotos-config-card/spec.md
//
// Sección del Dashboard que renderea una card DESTACADA por cada
// capacidad opcional ACTIVA, usando la metadata del registry F040
// (foto real + título + acción principal al módulo + botón ⚙️).
//
// Se inserta entre el reel de descubrimiento (capacidades NO activas)
// y el `DashboardModuleGrid` (que sigue mostrando todos los módulos
// como cards básicas por categoría). Las activas quedan tanto acá
// (visualmente destacadas con foto) como en el grid (organizadas por
// categoría) — son dos puntos de entrada distintos para el tendero
// 50+.
//
// Si NO hay capacidades opcionales activas, retorna `SizedBox.shrink`
// — la sección no aparece en el Dashboard de un tenant nuevo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/dashboard_modules.dart';
import '../screens/capabilities/capabilities_registry.dart';
import '../screens/capabilities/capability_scaffold.dart';
import '../screens/quotes/quote_capability_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/business_capability_map.dart';

class ActiveCapabilitiesSection extends StatelessWidget {
  final FeatureFlags flags;

  /// Callback opcional para refrescar el Dashboard tras volver de la
  /// pantalla de capacidad (p. ej. si el tendero la apagó).
  final VoidCallback? onReturned;

  const ActiveCapabilitiesSection({
    super.key,
    required this.flags,
    this.onReturned,
  });

  @override
  Widget build(BuildContext context) {
    // Recolectamos las capacidades opcionales activadas que TIENEN
    // entrada en el registry F040. Si una capacidad está activa pero
    // no en el registry (caso teórico), cae al grid normal.
    final active = dashboardModules
        .where((m) =>
            m.layer == ModuleLayer.optional &&
            capabilityEnabled(m.capability, flags) &&
            (m.capability == OptionalCapability.quotes ||
                capabilitiesRegistry.containsKey(m.capability)))
        .toList();

    if (active.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '⚡ Sus capacidades activas',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          for (final m in active) ...[
            _ActiveCapabilityCard(
              module: m,
              onReturned: onReturned,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Card individual: foto + título/tagline + acción principal al módulo
/// + chip ⚙️ a la pantalla de configuración de la capacidad.
class _ActiveCapabilityCard extends StatelessWidget {
  final DashboardModule module;
  final VoidCallback? onReturned;

  const _ActiveCapabilityCard({required this.module, this.onReturned});

  // Cotizaciones tiene pantalla propia (settings de validez).
  Widget _capabilityScreen() {
    if (module.capability == OptionalCapability.quotes) {
      return const QuoteCapabilityScreen();
    }
    final meta = capabilitiesRegistry[module.capability]!;
    return CapabilityScaffold(metadata: meta);
  }

  String _photoUrlOrEmpty() {
    if (module.capability == OptionalCapability.quotes) {
      // Misma foto Pexels que `QuoteCapabilityScreen`. Si cambia allá,
      // hay que actualizarla acá — no es un duplicado lógico, sólo
      // visual; un mismatch no rompe nada.
      return 'https://images.pexels.com/photos/95916/pexels-photo-95916.jpeg?auto=compress&cs=tinysrgb&w=600&h=400&fit=crop';
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

  Future<void> _openModule(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => module.destination()),
    );
    onReturned?.call();
  }

  Future<void> _openSettings(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _capabilityScreen()),
    );
    onReturned?.call();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor();
    final fallback = _fallbackIcon();
    final photoUrl = _photoUrlOrEmpty();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.18), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero compacto con foto.
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            child: SizedBox(
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: accent.withValues(alpha: 0.15)),
                  if (photoUrl.isNotEmpty)
                    Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _photoPlaceholder(accent, fallback),
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return _photoPlaceholder(accent, fallback);
                      },
                    )
                  else
                    _photoPlaceholder(accent, fallback),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        module.subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Botón ⚙️ — abre la pantalla dedicada de la capacidad.
                Material(
                  color: accent.withValues(alpha: 0.10),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openSettings(context),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(Icons.settings_rounded,
                          color: accent, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // CTA principal — abre el módulo funcional.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _openModule(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: Icon(module.icon, size: 22),
                label: Text(
                  'Abrir ${module.title.toLowerCase()}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder(Color accent, IconData icon) {
    return Container(
      color: accent.withValues(alpha: 0.15),
      child: Center(
        child: Icon(icon, size: 48, color: accent),
      ),
    );
  }
}
