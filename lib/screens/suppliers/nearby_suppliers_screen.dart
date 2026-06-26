// Spec: specs/075-proveedores-b2b/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

  /// Título del header. Por defecto "Proveedores en VendIA" (directorio B2B);
  /// otros llamadores pueden personalizarlo.
  final String title;

  const NearbySuppliersScreen({
    super.key,
    this.api,
    this.title = 'Proveedores en VendIA',
  });

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
  LatLng? _origin;
  bool _mapView = false; // false = lista, true = mapa
  final MapController _mapCtrl = MapController();

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
      final res = await _api.fetchNearbySuppliersFull(radiusKm: _radius);
      final list = (res['data'] as List).cast<Map<String, dynamic>>();
      final o = res['origin'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _suppliers = list;
        _origin = (o != null && o['lat'] != null && o['lng'] != null)
            ? LatLng((o['lat'] as num).toDouble(), (o['lng'] as num).toDouble())
            : null;
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
        title: Text(widget.title, style: AppUI.title),
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
            // Toggle Lista / Mapa.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppUI.s16),
              child: Row(children: [
                _viewChip('Lista', Icons.view_list_rounded, !_mapView,
                    () => setState(() => _mapView = false)),
                const SizedBox(width: 6),
                _viewChip('Mapa', Icons.map_rounded, _mapView,
                    () => setState(() => _mapView = true)),
              ]),
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
    if (_mapView) return _mapBody();
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
        onTap: () => _openCatalog(_suppliers[i]),
      ),
    );
  }

  void _openCatalog(Map<String, dynamic> s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SupplierCatalogScreen(
        supplierId: s['id'].toString(),
        supplierName: (s['business_name'] ?? '').toString(),
      ),
    ));
  }

  Widget _viewChip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: selected ? AppTheme.primary : AppUI.inkSoft),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 13)),
      ]),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primary.withValues(alpha: 0.15),
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppUI.radiusSm),
        side: BorderSide(color: selected ? AppTheme.primary : AppUI.border),
      ),
    );
  }

  // Vista de MAPA: origen (mi negocio) + un pin por proveedor (toca → catálogo).
  Widget _mapBody() {
    final origin = _origin;
    if (origin == null) {
      return const _Centered(
        icon: Icons.location_off_rounded,
        title: 'Fije la ubicación de su negocio para ver el mapa.',
      );
    }
    return Stack(children: [
      FlutterMap(
        mapController: _mapCtrl,
        options: MapOptions(
          initialCenter: origin,
          initialZoom: _radius <= 1 ? 15 : (_radius <= 5 ? 13.5 : 12.5),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'store.vendia.app',
          ),
          MarkerLayer(markers: [
            Marker(
              point: origin,
              width: 44,
              height: 44,
              child: const Icon(Icons.my_location_rounded,
                  color: AppTheme.primary, size: 30),
            ),
            for (final s in _suppliers)
              if (s['lat'] != null && s['lng'] != null)
                Marker(
                  point: LatLng((s['lat'] as num).toDouble(),
                      (s['lng'] as num).toDouble()),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => _openCatalog(s),
                    child: Icon(
                        (s['business_types'] as List?)
                                    ?.any((t) => t.toString().contains('agricola')) ==
                                true
                            ? Icons.grass_rounded
                            : Icons.warehouse_rounded,
                        color: AppTheme.error,
                        size: 32),
                  ),
                ),
          ]),
        ],
      ),
      if (_suppliers.isEmpty)
        Positioned(
          left: AppUI.s16,
          right: AppUI.s16,
          top: AppUI.s8,
          child: Container(
            padding: const EdgeInsets.all(AppUI.s12),
            decoration: AppUI.card(r: 10),
            child: const Text(
                'No hay proveedores en este radio. Pruebe ampliar la distancia.',
                style: AppUI.bodySoft),
          ),
        ),
    ]);
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
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(AppUI.s12),
        decoration: AppUI.card(r: 18),
        child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(isAgro ? Icons.grass_rounded : Icons.warehouse_rounded,
                color: AppTheme.primary, size: 24),
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
