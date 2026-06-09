// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
//
// Grid adaptativo del Dashboard: agrupa los módulos visibles en las 4
// categorías con encabezado (VENDER / INVENTARIO / CLIENTES / MI
// NEGOCIO). El módulo "Registrar venta" se renderiza destacado al
// inicio de VENDER.
//
// El widget es puro: recibe `businessType` + `flags` y deriva la lista
// con `visibleModulesFor(...)`. Esto lo hace testeable sin mockear el
// stack de API/Isar (ver test/widgets/dashboard_module_grid_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/dashboard_modules.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class DashboardModuleGrid extends StatelessWidget {
  /// Tipo de negocio del tenant — gatea los módulos `byType`.
  final String? businessType;

  /// Feature flags del tenant — gatean los módulos `optional`.
  final FeatureFlags flags;

  /// F041 — módulos ya resueltos desde el catálogo dinámico. Si es null
  /// (sin catálogo / offline en primer arranque), se cae al cálculo
  /// compilado `visibleModulesFor` (bundle), preservando el comportamiento.
  final List<DashboardModule>? modules;

  const DashboardModuleGrid({
    super.key,
    required this.businessType,
    required this.flags,
    this.modules,
  });

  @override
  Widget build(BuildContext context) {
    final visible = modules ?? visibleModulesFor(businessType, flags);

    final sections = <Widget>[];
    for (final category in ModuleCategory.values) {
      final modules =
          visible.where((m) => m.category == category).toList();
      if (modules.isEmpty) continue;
      sections.add(_CategorySection(
        category: category,
        modules: modules,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }
}

/// Una sección con encabezado + las tarjetas de sus módulos.
class _CategorySection extends StatelessWidget {
  final ModuleCategory category;
  final List<DashboardModule> modules;

  const _CategorySection({required this.category, required this.modules});

  @override
  Widget build(BuildContext context) {
    // "Registrar venta" va destacado al inicio de su categoría.
    final featured = modules
        .where((m) => m.id == 'registrar_venta')
        .toList();
    final rest = modules.where((m) => m.id != 'registrar_venta').toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado de categoría ──────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              category.label,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          for (final m in featured) ...[
            _FeaturedModuleCard(module: m),
            const SizedBox(height: 10),
          ],
          for (final m in rest) ...[
            _ModuleCard(module: m),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta destacada — más alta y con degradado. Solo "Registrar venta".
class _FeaturedModuleCard extends StatelessWidget {
  final DashboardModule module;

  const _FeaturedModuleCard({required this.module});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: module.title,
      child: GestureDetector(
        key: Key('dashboard_featured_${module.id}'),
        onTap: () => _navigate(context, module),
        child: Container(
          key: Key('dashboard_module_${module.id}'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3A8A).withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(module.icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      module.subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.white, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta estándar de módulo.
class _ModuleCard extends StatelessWidget {
  final DashboardModule module;

  const _ModuleCard({required this.module});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: module.title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('dashboard_module_${module.id}'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => _navigate(context, module),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: module.color.withValues(alpha: 0.10),
                width: 1,
              ),
              boxShadow: [
                // Sombra teñida con el color del módulo — da profundidad
                // y refuerza la identidad de cada categoría sin saturar.
                BoxShadow(
                  color: module.color.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.025),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                // Ícono dentro de un container con gradient diagonal
                // del color del módulo — más vivo que el flat color
                // y consistente con el hero del Welcome modernizado.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        module.color.withValues(alpha: 0.18),
                        module.color.withValues(alpha: 0.32),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: module.color.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(module.icon, color: module.color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          height: 1.2,
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
                // Chevron más sutil — el color del módulo solo en hover
                // visual de la sombra. El gris suave no compite con el
                // ícono coloreado.
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade400, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _navigate(BuildContext context, DashboardModule module) {
  HapticFeedback.lightImpact();
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => module.destination()),
  );
}
