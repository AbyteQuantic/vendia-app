// Spec: specs/081-mercado-cercano-mapa/spec.md
//
// Mercado cercano: MAPA con las tiendas/mercados reales (Ara, D1, Éxito,
// Olímpica…) alrededor del negocio. Datos de OpenStreetMap (backend
// /market/nearby), gratis. Tocar un pin muestra nombre, distancia y dirección.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../../widgets/use_my_location_button.dart';

class MarketMapScreen extends StatefulWidget {
  final ApiService? api;
  const MarketMapScreen({super.key, this.api});

  @override
  State<MarketMapScreen> createState() => _MarketMapScreenState();
}

class _MarketMapScreenState extends State<MarketMapScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  final MapController _mapCtrl = MapController();
  final List<double> _radios = [1, 5, 10];
  double _radius = 5;

  bool _loading = true;
  String? _error;
  LatLng? _origin;
  List<Map<String, dynamic>> _markets = [];
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
    });
    try {
      final res = await _api.fetchNearbyMarkets(radiusKm: _radius);
      final origin = (res['origin'] as Map?)?.cast<String, dynamic>();
      final data = ((res['data'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _origin = origin == null
            ? null
            : LatLng((origin['lat'] as num).toDouble(),
                (origin['lng'] as num).toDouble());
        _markets = data;
        _error = res['source_error'] as String?;
        _loading = false;
      });
      // Recentrar el mapa en el negocio cuando llega la ubicación.
      if (_origin != null) {
        _mapCtrl.move(_origin!, _zoomForRadius(_radius));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar el mapa.';
        _loading = false;
      });
    }
  }

  double _zoomForRadius(double km) => km <= 1 ? 15 : (km <= 5 ? 13.5 : 12.5);

  bool _capturing = false;

  /// Captura el GPS real y lo guarda como ubicación del negocio, luego recarga.
  /// Para cuando el pin está en el lugar equivocado (geo mal capturada). Spec 072.
  Future<void> _recaptureLocation() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('Permiso de ubicación denegado. Actívelo para corregir su ubicación.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      String city = '';
      try {
        final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) city = places.first.locality ?? '';
      } catch (_) {}
      await _api.updateStoreLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          city: city);
      if (!mounted) return;
      _snack(city.isNotEmpty ? 'Ubicación actualizada · $city' : 'Ubicación actualizada',
          ok: true);
      await _load();
    } catch (_) {
      _snack('No pudimos obtener su ubicación. Intente de nuevo.');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _snack(String m, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: ok ? AppTheme.success : AppTheme.error));
  }

  bool get _needsLocation =>
      _error != null &&
      (_error!.toLowerCase().contains('ubicación') ||
          _error!.toLowerCase().contains('ubicacion'));

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _capturing ? null : _recaptureLocation,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: _capturing
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.my_location_rounded),
        label: const Text('Mi ubicación'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s8),
              child: Text(
                  'Tiendas y mercados cerca de su negocio. Toque un punto para ver la distancia.',
                  style: AppUI.bodySoft),
            ),
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
    if (_needsLocation || _origin == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppUI.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.location_off_rounded, size: 44, color: AppUI.inkSoft),
            const SizedBox(height: AppUI.s12),
            Text(
                _error ??
                    'Fije la ubicación de su negocio para ver el mercado cercano.',
                textAlign: TextAlign.center, style: AppUI.bodySoft),
            const SizedBox(height: AppUI.s8),
            UseMyLocationButton(onDone: _load),
          ]),
        ),
      );
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapCtrl,
          options: MapOptions(
            initialCenter: _origin!,
            initialZoom: _zoomForRadius(_radius),
            onTap: (_, __) => setState(() => _selected = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'store.vendia.app',
            ),
            MarkerLayer(markers: [
              // El negocio (origen).
              Marker(
                point: _origin!,
                width: 44,
                height: 44,
                child: const Icon(Icons.my_location_rounded,
                    color: AppTheme.primary, size: 30),
              ),
              // Las tiendas/mercados.
              for (final m in _markets)
                Marker(
                  point: LatLng((m['lat'] as num).toDouble(),
                      (m['lng'] as num).toDouble()),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = m),
                    child: Icon(Icons.storefront_rounded,
                        color: _selected == m ? AppTheme.success : AppTheme.error,
                        size: 32),
                  ),
                ),
            ]),
          ],
        ),
        // Aviso cuando no hay tiendas o la fuente externa falló.
        if (_markets.isEmpty)
          Positioned(
            left: AppUI.s16,
            right: AppUI.s16,
            top: AppUI.s8,
            child: Container(
              padding: const EdgeInsets.all(AppUI.s12),
              decoration: AppUI.card(r: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    _error ??
                        'No encontramos tiendas en este radio. Pruebe ampliar a 10 km. '
                            'Si el punto azul no es su negocio, toque "Mi ubicación".',
                    style: AppUI.bodySoft),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _load,
                    child: const Text('Reintentar'),
                  ),
                ),
              ]),
            ),
          ),
        // Tarjeta del punto seleccionado (sobre el FAB).
        if (_selected != null)
          Positioned(
            left: AppUI.s16,
            right: AppUI.s16,
            bottom: 84,
            child: _MarketCard(data: _selected!),
          ),
      ],
    );
  }
}

class _MarketCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _MarketCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final addr = (data['address'] ?? '').toString();
    final dist = (data['distance_km'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 12),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppUI.radiusSm),
          ),
          child: const Icon(Icons.storefront_rounded, color: AppTheme.error, size: 22),
        ),
        const SizedBox(width: AppUI.s12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppUI.bodyStrong),
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.near_me_rounded, size: 13, color: AppUI.inkSoft),
              const SizedBox(width: 3),
              Text('${dist.toStringAsFixed(1)} km', style: AppUI.bodySoft),
              if (addr.isNotEmpty) ...[
                const Text('  ·  ', style: TextStyle(color: AppUI.inkSoft)),
                Flexible(child: Text(addr, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppUI.bodySoft)),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}
