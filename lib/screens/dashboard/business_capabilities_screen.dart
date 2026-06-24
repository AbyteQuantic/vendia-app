// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// "Capacidades del negocio" — pantalla única que reúne TODAS las
// capacidades opcionales del tenant en un solo lugar (spec §4.3).
// Reemplaza la dispersión previa: F023 vivía en "Perfil del Negocio";
// otras quedaban sueltas.
//
// Regla clave (AC-06): TODA capacidad opcional es activable por
// CUALQUIER tipo de negocio — incluida "Mesas" para una tienda_barrio.
// El `business_type` solo define el default pre-activado en el
// onboarding, NUNCA restringe lo que se puede activar acá.
//
// F037: la pantalla acepta `highlightCapability` para resaltar el tile
// correspondiente con un pulso visual cuando el dueño llega desde una
// card del reel del Dashboard — guía el ojo del tendero 50+ al toggle
// exacto que quería activar.
//
// El cuaderno de créditos (F035) NO se duplica: esta pantalla enlaza
// a CreditSettingsScreen.
//
// Persiste vía PATCH /store/profile — el backend recalcula los
// feature_flags a partir del `config` bag de toggles.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/business_capability_map.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'credit_settings_screen.dart';

/// Metadata visual de cada capacidad opcional.
class _CapabilityInfo {
  final OptionalCapability capability;
  final String toggleKey;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const _CapabilityInfo({
    required this.capability,
    required this.toggleKey,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const List<_CapabilityInfo> _capabilities = [
  _CapabilityInfo(
    capability: OptionalCapability.services,
    toggleKey: 'cap_toggle_services',
    title: 'Servicios o trabajos por encargo',
    description: 'Cobre arreglos, instalaciones o cortes a domicilio',
    icon: Icons.handyman_rounded,
    color: Color(0xFF7C3AED),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.fractionalUnits,
    toggleKey: 'cap_toggle_fractional_units',
    title: 'Venta a granel o fraccionada',
    description: 'Arroz por libra, aceite por litro, granos sueltos',
    icon: Icons.scale_rounded,
    color: Color(0xFFD97706),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.tables,
    toggleKey: 'cap_toggle_tables',
    title: 'Atención en mesas',
    description: 'Comedor, sala de espera o mesas para sus clientes',
    icon: Icons.table_restaurant_rounded,
    color: Color(0xFF3B82F6),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.priceTiers,
    toggleKey: 'cap_toggle_price_tiers',
    title: 'Precios mayorista y minorista',
    description: 'Maneje precios distintos según el tipo de cliente',
    icon: Icons.sell_rounded,
    color: Color(0xFF059669),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.customerManagement,
    toggleKey: 'cap_toggle_customer_management',
    title: 'Gestión de clientes',
    description: 'Sepa quién le compra: historial y total gastado',
    icon: Icons.people_outline,
    color: Color(0xFF1A2FA0),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.quotes,
    toggleKey: 'cap_toggle_quotes',
    title: 'Cotizaciones',
    description: 'Arme propuestas de precio antes de la venta',
    icon: Icons.description_outlined,
    color: Color(0xFF1A2FA0),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.promotions,
    toggleKey: 'cap_toggle_promotions',
    title: 'Promociones',
    description: 'Avísele a sus clientes de ofertas por WhatsApp',
    icon: Icons.campaign_rounded,
    color: Color(0xFFD97706),
  ),
  // F037: Marketing Hub deja de ser core y se vuelve toggle.
  _CapabilityInfo(
    capability: OptionalCapability.marketingHub,
    toggleKey: 'cap_toggle_marketing_hub',
    title: 'Marketing y Combos',
    description: 'Combos, banners con IA y catálogo en línea',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFF7C3AED),
  ),
  // F037: módulos que migraron de byType (rígido por tipo) a opt-in
  // para que CUALQUIER negocio pueda activarlos desde el reel/lista.
  _CapabilityInfo(
    capability: OptionalCapability.recipes,
    toggleKey: 'cap_toggle_recipes',
    title: 'Recetas y Platos',
    description: 'Arme un plato y vea su costo y ganancia',
    icon: Icons.restaurant_menu_rounded,
    color: Color(0xFFEE5A24),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.supplies,
    toggleKey: 'cap_toggle_supplies',
    title: 'Mis Insumos',
    description: 'Materia prima: stock, mínimos y costo',
    icon: Icons.kitchen_rounded,
    color: Color(0xFFD97706),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.furnitureJobs,
    toggleKey: 'cap_toggle_furniture_jobs',
    title: 'Trabajos de Muebles',
    description: 'Cotice, fabrique y repare por encargo',
    icon: Icons.handyman_rounded,
    color: Color(0xFF1E40AF),
  ),
  _CapabilityInfo(
    capability: OptionalCapability.purchaseOrders,
    toggleKey: 'cap_toggle_purchase_orders',
    title: 'Órdenes de Compra',
    description: 'Pida a proveedores y reciba el stock',
    icon: Icons.shopping_cart_rounded,
    color: Color(0xFF0D9668),
  ),
];

class BusinessCapabilitiesScreen extends StatefulWidget {
  /// Inyección de [ApiService] para tests. En producción se crea uno.
  final ApiService? apiOverride;

  /// F037: capacidad a resaltar con un pulso visual al entrar. La pasa
  /// el reel del Dashboard para guiar el ojo del tendero al toggle que
  /// quería activar. Sin valor → sin animación.
  final OptionalCapability? highlightCapability;

  const BusinessCapabilitiesScreen({
    super.key,
    this.apiOverride,
    this.highlightCapability,
  });

  @override
  State<BusinessCapabilitiesScreen> createState() =>
      _BusinessCapabilitiesScreenState();
}

class _BusinessCapabilitiesScreenState
    extends State<BusinessCapabilitiesScreen>
    with SingleTickerProviderStateMixin {
  late final ApiService _api;
  bool _loading = true;
  bool _saving = false;

  /// Estado de cada toggle, indexado por [OptionalCapability].
  final Map<OptionalCapability, bool> _enabled = {
    for (final c in OptionalCapability.values) c: false,
  };

  /// F037: controlador del pulso (escala + tinte) del tile resaltado.
  AnimationController? _pulseCtrl;
  Animation<double>? _scaleAnim;
  Animation<double>? _tintAnim;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    if (widget.highlightCapability != null) {
      _pulseCtrl = AnimationController(
        vsync: this,
        // ~1s por pulso × 2 pulsos = ~2s total (AC-05).
        duration: const Duration(milliseconds: 1000),
      );
      _scaleAnim = TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 1.1)
                .chain(CurveTween(curve: Curves.easeOut)),
            weight: 50),
        TweenSequenceItem(
            tween: Tween(begin: 1.1, end: 1.0)
                .chain(CurveTween(curve: Curves.easeIn)),
            weight: 50),
      ]).animate(_pulseCtrl!);
      _tintAnim = TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: 0.0, end: 1.0)
                .chain(CurveTween(curve: Curves.easeOut)),
            weight: 50),
        TweenSequenceItem(
            tween: Tween(begin: 1.0, end: 0.0)
                .chain(CurveTween(curve: Curves.easeIn)),
            weight: 50),
      ]).animate(_pulseCtrl!);
    }
    _load();
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _api.fetchBusinessProfile();
      final flags = (data['feature_flags'] is Map)
          ? FeatureFlags.fromJson(
              (data['feature_flags'] as Map).cast<String, dynamic>())
          : const FeatureFlags();
      if (mounted) {
        setState(() {
          // El perfil expone los toggles tanto a nivel raíz como dentro
          // de feature_flags — leemos cualquiera de los dos (lo que
          // venga true gana) para ser robustos al contrato del backend.
          _enabled[OptionalCapability.services] =
              data['enable_services'] == true || flags.enableServices;
          _enabled[OptionalCapability.fractionalUnits] =
              data['enable_fractional_units'] == true ||
                  flags.enableFractionalUnits;
          _enabled[OptionalCapability.tables] =
              data['enable_tables'] == true || flags.enableTables;
          _enabled[OptionalCapability.priceTiers] =
              data['enable_price_tiers'] == true || flags.enablePriceTiers;
          _enabled[OptionalCapability.customerManagement] =
              data['enable_customer_management'] == true ||
                  flags.enableCustomerManagement;
          _enabled[OptionalCapability.quotes] =
              data['enable_quotes'] == true || flags.enableQuotes;
          _enabled[OptionalCapability.promotions] =
              data['enable_promotions'] == true || flags.enablePromotions;
          _enabled[OptionalCapability.marketingHub] =
              data['enable_marketing_hub'] == true || flags.enableMarketingHub;
          // F037: módulos que migraron de byType a opcional con
          // backfill para tenants que ya tenían data legacy.
          _enabled[OptionalCapability.recipes] =
              data['enable_recipes'] == true || flags.enableRecipes;
          _enabled[OptionalCapability.supplies] =
              data['enable_supplies'] == true || flags.enableSupplies;
          _enabled[OptionalCapability.furnitureJobs] =
              data['enable_furniture_jobs'] == true ||
                  flags.enableFurnitureJobs;
          _enabled[OptionalCapability.purchaseOrders] =
              data['enable_purchase_orders'] == true ||
                  flags.enablePurchaseOrders;
          _loading = false;
        });
        _maybeStartPulse();
      }
    } catch (_) {
      // Offline / error — quedamos con todo OFF; el dueño puede
      // reintentar guardando, que vuelve a leer al cerrar.
      if (mounted) {
        setState(() => _loading = false);
        _maybeStartPulse();
      }
    }
  }

  /// F037: dispara el pulso del tile resaltado tras el primer paint.
  /// Se invoca al terminar `_load` (con o sin éxito) para que el pulso
  /// ocurra cuando el dueño ve la pantalla, no antes.
  void _maybeStartPulse() {
    if (!mounted || _pulseCtrl == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pulseCtrl == null) return;
      _pulseCtrl!
        ..reset()
        ..forward().then((_) {
          if (!mounted || _pulseCtrl == null) return;
          _pulseCtrl!.forward(from: 0.0);
        });
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      // Mismo `config` bag que usa business_profile_screen — el backend
      // recalcula feature_flags a partir de estos toggles.
      final updates = <String, dynamic>{
        'config': {
          'offers_services': _enabled[OptionalCapability.services],
          'sells_by_weight': _enabled[OptionalCapability.fractionalUnits],
          'has_tables': _enabled[OptionalCapability.tables],
          'enable_price_tiers': _enabled[OptionalCapability.priceTiers],
          'enable_customer_management':
              _enabled[OptionalCapability.customerManagement],
          'enable_quotes': _enabled[OptionalCapability.quotes],
          'enable_promotions': _enabled[OptionalCapability.promotions],
          'enable_marketing_hub':
              _enabled[OptionalCapability.marketingHub],
          // F037: módulos que migraron de byType a opcional.
          'enable_recipes': _enabled[OptionalCapability.recipes],
          'enable_supplies': _enabled[OptionalCapability.supplies],
          'enable_furniture_jobs':
              _enabled[OptionalCapability.furnitureJobs],
          'enable_purchase_orders':
              _enabled[OptionalCapability.purchaseOrders],
        },
      };
      final response = await _api.updateBusinessProfile(updates);
      // Refrescar el cache local de feature_flags para que el
      // Dashboard vea las capacidades activadas/desactivadas al
      // volver (lee de disco, no del backend).
      await AuthService().saveFeatureFlagsFromProfile(response);
      if (!mounted) return;
      _showSnack('Capacidades guardadas');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _showSnack('No se pudo guardar: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 17)),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Capacidades del negocio',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _buildBody(),
      bottomNavigationBar: _loading ? null : _buildSaveBar(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      children: [
        const Text(
          'Active lo que su negocio hace. Puede prender o apagar '
          'cualquier capacidad cuando quiera.',
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),
        for (final info in _capabilities) ...[
          _CapabilityCard(
            info: info,
            value: _enabled[info.capability] ?? false,
            onChanged: (v) =>
                setState(() => _enabled[info.capability] = v),
            highlight: widget.highlightCapability == info.capability,
            scaleAnim: _scaleAnim,
            tintAnim: _tintAnim,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        // El cuaderno de créditos vive en su pantalla dedicada (F035).
        _CreditLinkCard(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const CreditSettingsScreen()),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSaveBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      child: SizedBox(
        height: 60,
        child: ElevatedButton.icon(
          key: const Key('cap_save_button'),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : const Icon(Icons.check_rounded, size: 24),
          label: Text(_saving ? 'Guardando...' : 'Guardar cambios',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

/// Tarjeta de una capacidad con su toggle.
///
/// Cuando [highlight] es `true` y vienen [scaleAnim] + [tintAnim], la
/// tarjeta pulsa con escala 1.0→1.1→1.0 y un tinte de color sutil del
/// color de la capacidad durante ~2 segundos. Guía visual del reel
/// (F037 AC-05).
class _CapabilityCard extends StatelessWidget {
  final _CapabilityInfo info;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool highlight;
  final Animation<double>? scaleAnim;
  final Animation<double>? tintAnim;

  const _CapabilityCard({
    required this.info,
    required this.value,
    required this.onChanged,
    this.highlight = false,
    this.scaleAnim,
    this.tintAnim,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: SwitchListTile(
        key: Key(info.toggleKey),
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.primary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        secondary: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: info.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(info.icon, color: info.color, size: 24),
        ),
        title: Text(
          info.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            info.description,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
          ),
        ),
      ),
    );

    if (!highlight || scaleAnim == null || tintAnim == null) {
      return tile;
    }

    return AnimatedBuilder(
      animation: scaleAnim!,
      builder: (context, child) {
        final tintIntensity = tintAnim!.value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: scaleAnim!.value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: info.color
                  .withValues(alpha: 0.18 * tintIntensity),
              boxShadow: tintIntensity > 0
                  ? [
                      BoxShadow(
                        color: info.color
                            .withValues(alpha: 0.32 * tintIntensity),
                        blurRadius: 18 * tintIntensity,
                        spreadRadius: 2 * tintIntensity,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: tile,
    );
  }
}

/// Enlace a la pantalla del cuaderno de créditos (F035).
class _CreditLinkCard extends StatelessWidget {
  final VoidCallback onTap;

  const _CreditLinkCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('cap_credit_link'),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF6D28D9).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.menu_book_rounded,
                  color: Color(0xFF6D28D9), size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cuaderno de créditos',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  Text('Habilitar el fiado y su vocabulario',
                      style: TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF6D28D9), size: 24),
          ],
        ),
      ),
    );
  }
}
