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

  const DashboardModuleGrid({
    super.key,
    required this.businessType,
    required this.flags,
  });

  @override
  Widget build(BuildContext context) {
    final visible = visibleModulesFor(businessType, flags);

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
      child: GestureDetector(
        key: Key('dashboard_module_${module.id}'),
        onTap: () => _navigate(context, module),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: module.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, color: module.color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      module.subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: module.color, size: 24),
            ],
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
