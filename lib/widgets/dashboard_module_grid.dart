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
import 'dashboard_ui_kit.dart';

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

/// Una sección con encabezado + sus módulos en una LISTA AGRUPADA
/// (inset grouped, estilo Ajustes de iOS): un solo contenedor blanco con
/// bordes redondeados y divisores internos sutiles — sin sombra por ítem.
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
      padding: const EdgeInsets.fromLTRB(DashUI.s16, DashUI.s24, DashUI.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado de categoría — más presencia (SemiBold) ──
          Padding(
            padding: const EdgeInsets.only(left: DashUI.s8, bottom: 12),
            child: Text(
              category.label,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: DashUI.inkSoft,
                letterSpacing: 1.1,
              ),
            ),
          ),
          for (final m in featured) ...[
            _FeaturedModuleCard(module: m),
            const SizedBox(height: 12),
          ],
          // ── Grupo: una sola tarjeta con divisores internos ──────
          if (rest.isNotEmpty)
            Container(
              decoration: DashUI.card(),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < rest.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        indent: 70, // alinea con el texto, pasado el ícono
                        color: DashUI.divider,
                      ),
                    _ModuleRow(module: rest[i]),
                  ],
                ],
              ),
            ),
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
          // Azul marino profundo con degradado EXTREMADAMENTE sutil —
          // premium, no el azul sólido básico. Sin subtítulo: el título
          // ya dice todo (cero redundancia).
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF101F4E), Color(0xFF1E3A8A)],
            ),
            borderRadius: BorderRadius.circular(DashUI.rCard),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF101F4E).withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(module.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  module.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

/// Fila de módulo dentro del grupo (estilo Ajustes de iOS): sin tarjeta ni
/// sombra propia — el contenedor agrupado las aporta. Ícono con fondo al
/// 10% de su color; título #1F2937 y subtítulo #6B7280.
class _ModuleRow extends StatelessWidget {
  final DashboardModule module;

  const _ModuleRow({required this.module});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: module.title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('dashboard_module_${module.id}'),
          onTap: () => _navigate(context, module),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: DashUI.s16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: module.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: DashUI.ink,
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
                          color: DashUI.inkSoft,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.grey.shade300, size: 22),
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
