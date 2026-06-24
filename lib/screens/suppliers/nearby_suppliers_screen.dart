// Spec: specs/075-proveedores-b2b/spec.md
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/use_my_location_button.dart';
import 'supplier_catalog_screen.dart';

/// Mercado cercano (Spec 075 F2): el tendero ve los proveedores con ubicación
/// real dentro de un radio, ordenados por distancia. Conecta — el pedido se
/// cierra por WhatsApp (F3). Solo lectura cross-tenant.
class NearbySuppliersScreen extends StatefulWidget {
  final ApiService? api;
  const NearbySuppliersScreen({super.key, this.api});

  @override
  State<NearbySuppliersScreen> createState() => _NearbySuppliersScreenState();
}

class _NearbySuppliersScreenState extends State<NearbySuppliersScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  final List<double> _radios = [1, 5, 10];
  double _radius = 5;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.fetchNearbySuppliers(radiusKm: _radius);
      if (!mounted) return;
      setState(() {
        _suppliers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar los proveedores.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Mercado cercano', style: AppUI.title),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s8),
              child: Text('Proveedores cerca de su negocio. Pida directo y ahorre flete.',
                  style: AppUI.bodySoft),
            ),
            // Selector de radio.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppUI.s16),
              child: Row(
                children: [
                  const Text('A la redonda:', style: AppUI.sectionLabel),
                  const SizedBox(width: AppUI.s8),
                  for (final r in _radios)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        key: Key('radius_${r.toInt()}'),
                        label: Text('${r.toInt()} km'),
                        selected: _radius == r,
                        onSelected: (_) {
                          setState(() => _radius = r);
                          _load();
                        },
                        selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppUI.radiusSm),
                          side: BorderSide(
                              color: _radius == r ? AppTheme.primary : AppUI.border),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppUI.s8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      // Si falta la ubicación, el empty-state es ACCIONABLE: capturar GPS aquí
      // mismo y recargar (no solo "Reintentar" en loop).
      final needsLocation = _error!.toLowerCase().contains('ubicación') ||
          _error!.toLowerCase().contains('ubicacion');
      return _Centered(
        icon: Icons.location_off_rounded,
        title: _error!,
        action: needsLocation
            ? UseMyLocationButton(onDone: _load)
            : TextButton(onPressed: _load, child: const Text('Reintentar')),
      );
    }
    if (_suppliers.isEmpty) {
      return const _Centered(
        icon: Icons.storefront_rounded,
        title: 'Aún no hay proveedores cerca a esta distancia.\nPruebe ampliar el radio.',
      );
    }
    return ListView.separated(
      key: const Key('nearby_suppliers_list'),
      padding: const EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s24),
      itemCount: _suppliers.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
      itemBuilder: (_, i) => _SupplierCard(
        data: _suppliers[i],
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupplierCatalogScreen(
            supplierId: _suppliers[i]['id'].toString(),
            supplierName: (_suppliers[i]['business_name'] ?? '').toString(),
          ),
        )),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _SupplierCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final types = (data['business_types'] as List?)?.cast<dynamic>() ?? const [];
    final isAgro = types.any((t) => t.toString().contains('agricola'));
    final name = (data['business_name'] ?? '').toString().replaceFirst('[SEED] ', '');
    final dist = (data['distance_km'] as num?)?.toDouble() ?? 0;
    final products = (data['product_count'] as num?)?.toInt() ?? 0;
    final expiring = (data['expiring_soon_count'] as num?)?.toInt() ?? 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(AppUI.s12),
        decoration: AppUI.card(r: 10),
        child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppUI.radiusSm),
            ),
            child: Icon(isAgro ? Icons.grass_rounded : Icons.warehouse_rounded,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: AppUI.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppUI.bodyStrong),
                    ),
                    const SizedBox(width: AppUI.s8),
                    MinimalBadge(label: isAgro ? 'Agrícola' : 'Mayorista', color: AppTheme.primary),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.near_me_rounded, size: 13, color: AppUI.inkSoft),
                    const SizedBox(width: 3),
                    Text('${dist.toStringAsFixed(1)} km',
                        style: const TextStyle(
                            fontSize: 13, color: AppUI.inkSoft,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const Text('  ·  ', style: TextStyle(color: AppUI.inkSoft)),
                    Text('$products productos', style: AppUI.bodySoft),
                  ],
                ),
                if (expiring > 0) ...[
                  const SizedBox(height: 6),
                  MinimalBadge(label: '$expiring por vencer · oferta', color: AppTheme.warning),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppUI.inkSoft),
        ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? action;
  const _Centered({required this.icon, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppUI.inkSoft),
            const SizedBox(height: AppUI.s12),
            Text(title, textAlign: TextAlign.center, style: AppUI.bodySoft),
            if (action != null) ...[const SizedBox(height: AppUI.s8), action!],
          ],
        ),
      ),
    );
  }
}
