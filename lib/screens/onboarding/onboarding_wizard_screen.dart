// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
//
// Wizard de onboarding (spec §4.4) — se muestra UNA sola vez, al
// primer ingreso tras el registro (`onboarding_completed=false`).
//
// 3 pasos en un PageView:
//   1. Confirmar el tipo de negocio.
//   2. Checklist de capacidades, pre-marcado según el tipo.
//   3. "¡Listo!".
//
// Botón "Configurar después" visible en TODO momento — saltar deja el
// negocio con el default de su tipo (la app es 100% usable, AC-08).
//
// Al terminar o saltar → PATCH /store/profile con
// `onboarding_completed=true` (+ las capacidades si las tocó) y se
// marca el flag en AuthService para no volver a mostrarlo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/business_capability_map.dart';

/// Tipos de negocio — 1:1 con models.ValidBusinessTypes del backend.
const List<(String, IconData, String)> _businessTypes = [
  ('tienda_barrio', Icons.store_rounded, 'Tienda de Barrio'),
  ('minimercado', Icons.local_grocery_store_rounded, 'Minimercado'),
  ('deposito_construccion', Icons.inventory_2_rounded,
      'Depósito / Ferretería'),
  ('restaurante', Icons.restaurant_rounded, 'Restaurante'),
  ('comidas_rapidas', Icons.fastfood_rounded, 'Comidas Rápidas'),
  ('bar', Icons.local_bar_rounded, 'Bar / Discoteca'),
  ('manufactura', Icons.precision_manufacturing_rounded, 'Manufactura'),
  ('reparacion_muebles', Icons.build_rounded, 'Reparación / Servicios'),
  ('emprendimiento_general', Icons.rocket_launch_rounded,
      'Emprendimiento General'),
];

/// Metadata de una capacidad opcional para el checklist del paso 2.
class _CapItem {
  final OptionalCapability capability;
  final String toggleKey;
  final String title;
  final IconData icon;

  const _CapItem(this.capability, this.toggleKey, this.title, this.icon);
}

const List<_CapItem> _capItems = [
  _CapItem(OptionalCapability.customerManagement,
      'onb_cap_customer_management', 'Manejo clientes', Icons.people_outline),
  _CapItem(OptionalCapability.tables, 'onb_cap_tables',
      'Tengo mesas', Icons.table_restaurant_rounded),
  _CapItem(OptionalCapability.services, 'onb_cap_services',
      'Cobro servicios', Icons.handyman_rounded),
  _CapItem(OptionalCapability.quotes, 'onb_cap_quotes',
      'Hago cotizaciones', Icons.description_outlined),
  _CapItem(OptionalCapability.fractionalUnits, 'onb_cap_fractional_units',
      'Vendo a granel', Icons.scale_rounded),
  _CapItem(OptionalCapability.priceTiers, 'onb_cap_price_tiers',
      'Precios mayorista/detal', Icons.sell_rounded),
  _CapItem(OptionalCapability.promotions, 'onb_cap_promotions',
      'Hago promociones', Icons.campaign_rounded),
];

class OnboardingWizardScreen extends StatefulWidget {
  /// Tipo de negocio elegido en el registro — pre-selecciona el paso 1.
  final String? initialBusinessType;

  /// Inyección de [ApiService] para tests.
  final ApiService? apiOverride;

  /// Se invoca tras completar / saltar el wizard (navega al Dashboard).
  final VoidCallback? onCompleted;

  const OnboardingWizardScreen({
    super.key,
    this.initialBusinessType,
    this.apiOverride,
    this.onCompleted,
  });

  @override
  State<OnboardingWizardScreen> createState() =>
      _OnboardingWizardScreenState();
}

class _OnboardingWizardScreenState extends State<OnboardingWizardScreen> {
  late final ApiService _api;
  final _pageCtrl = PageController();
  int _page = 0;
  bool _submitting = false;

  String? _selectedType;

  /// Estado del checklist de capacidades del paso 2.
  final Map<OptionalCapability, bool> _capEnabled = {
    for (final c in OptionalCapability.values) c: false,
  };

  /// El dueño tocó al menos un toggle — si no, no mandamos capacidades
  /// en el PATCH (deja el default del backend intacto, R2 del plan).
  bool _capsTouched = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _selectedType = widget.initialBusinessType;
    _applyDefaultsForType(_selectedType);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  /// Pre-marca el checklist con el default del tipo (espejo del backend).
  void _applyDefaultsForType(String? type) {
    final defaults = defaultCapabilitiesForType(type);
    for (final c in OptionalCapability.values) {
      _capEnabled[c] = defaults.contains(c);
    }
  }

  void _goToPage(int page) {
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  /// Termina o salta el wizard: PATCH onboarding_completed=true.
  Future<void> _finish({required bool skipped}) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    final updates = <String, dynamic>{
      'onboarding_completed': true,
    };
    // Si el dueño confirmó/cambió el tipo, lo enviamos.
    if (_selectedType != null) {
      updates['business_types'] = [_selectedType];
    }
    // Solo mandamos las capacidades si el dueño tocó el checklist —
    // saltar sin tocar nada deja el default del backend intacto (R2).
    if (!skipped && _capsTouched) {
      updates['config'] = {
        'enable_customer_management':
            _capEnabled[OptionalCapability.customerManagement],
        'has_tables': _capEnabled[OptionalCapability.tables],
        'offers_services': _capEnabled[OptionalCapability.services],
        'enable_quotes': _capEnabled[OptionalCapability.quotes],
        'sells_by_weight': _capEnabled[OptionalCapability.fractionalUnits],
        'enable_price_tiers': _capEnabled[OptionalCapability.priceTiers],
        'enable_promotions': _capEnabled[OptionalCapability.promotions],
      };
    }

    try {
      await _api.updateBusinessProfile(updates);
    } catch (_) {
      // Offline / error — igual marcamos el flag local para no atrapar
      // al dueño en el wizard. El backend se reconcilia luego.
    }
    // Marca el flag local pase lo que pase con la red — el wizard no
    // debe reaparecer (AC-07).
    try {
      await AuthService().updateOnboardingCompleted(true);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _submitting = false);
    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      body: SafeArea(
        child: Column(
          children: [
            // ── Barra superior: progreso + "Configurar después" ─────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(child: _ProgressDots(current: _page)),
                  TextButton(
                    key: const Key('onboarding_skip_button'),
                    onPressed:
                        _submitting ? null : () => _finish(skipped: true),
                    child: const Text(
                      'Configurar después',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _buildTypeStep(),
                  _buildCapabilitiesStep(),
                  _buildDoneStep(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Paso 1 — tipo de negocio ───────────────────────────────────────
  Widget _buildTypeStep() {
    return ListView(
      key: const Key('onboarding_step_type'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        const Text(
          '¿Qué tipo de negocio tenés?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Así VendIA se configura para lo que vos hacés.',
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.5,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: _businessTypes.map((t) {
            final value = t.$1;
            final selected = _selectedType == value;
            return GestureDetector(
              key: Key('onb_btype_$value'),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _selectedType = value;
                  // Al cambiar el tipo, re-sugerimos el checklist solo
                  // si el dueño todavía no lo tocó a mano (R2 del plan).
                  if (!_capsTouched) _applyDefaultsForType(value);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.1)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.borderColor,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(t.$2,
                        size: 26,
                        color: selected
                            ? AppTheme.primary
                            : AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.$3,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Paso 2 — checklist de capacidades ──────────────────────────────
  Widget _buildCapabilitiesStep() {
    return ListView(
      key: const Key('onboarding_step_capabilities'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        const Text(
          '¿Qué hacés en tu negocio?',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Marcamos lo típico de tu negocio. Cambialo si querés — '
          'podés ajustarlo después en cualquier momento.',
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        for (final item in _capItems) ...[
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: SwitchListTile(
              key: Key(item.toggleKey),
              value: _capEnabled[item.capability] ?? false,
              onChanged: (v) => setState(() {
                _capEnabled[item.capability] = v;
                _capsTouched = true;
              }),
              activeThumbColor: AppTheme.primary,
              secondary: Icon(item.icon,
                  size: 26, color: AppTheme.primary),
              title: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── Paso 3 — ¡Listo! ───────────────────────────────────────────────
  Widget _buildDoneStep() {
    return Center(
      key: const Key('onboarding_step_done'),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppTheme.success, size: 56),
            ),
            const SizedBox(height: 20),
            const Text(
              '¡Listo!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Su VendIA quedó configurada para su negocio. '
              'Puede cambiar lo que quiera en Mi Negocio → '
              'Capacidades del negocio.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ── Barra inferior: Atrás / Siguiente / Terminar ───────────────────
  Widget _buildBottomBar() {
    final isLast = _page == 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
      child: Row(
        children: [
          if (_page > 0)
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton(
                  key: const Key('onboarding_back_button'),
                  onPressed:
                      _submitting ? null : () => _goToPage(_page - 1),
                  child: const Text('Atrás',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          if (_page > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                key: Key(isLast
                    ? 'onboarding_finish_button'
                    : 'onboarding_next_button'),
                onPressed: _submitting
                    ? null
                    : isLast
                        ? () => _finish(skipped: false)
                        : () => _goToPage(_page + 1),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white),
                      )
                    : Text(
                        isLast ? 'Empezar a usar VendIA' : 'Siguiente',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicador de progreso de 3 pasos.
class _ProgressDots extends StatelessWidget {
  final int current;

  const _ProgressDots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final active = i <= current;
        return Container(
          margin: const EdgeInsets.only(right: 8),
          width: i == current ? 28 : 12,
          height: 8,
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : AppTheme.borderColor,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
