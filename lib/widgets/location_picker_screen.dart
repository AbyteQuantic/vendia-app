// Spec: specs/081-mercado-cercano-mapa/spec.md
//
// Selector de ubicación en mapa: el tendero toca dónde queda algo (p. ej. un
// proveedor) y se devuelve la coordenada. Reusa flutter_map + tiles OSM (gratis).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

class LocationPickerScreen extends StatefulWidget {
  /// Punto inicial (si ya había una ubicación). Si es null, centra en Colombia.
  final LatLng? initial;
  final String title;
  const LocationPickerScreen({super.key, this.initial, this.title = 'Fijar ubicación'});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Centro por defecto: Colombia (Bogotá) si no hay punto inicial.
  static const _fallback = LatLng(4.6097, -74.0817);
  late LatLng _picked = widget.initial ?? _fallback;
  bool _hasPick = false;

  @override
  void initState() {
    super.initState();
    _hasPick = widget.initial != null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title, style: AppUI.title),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppUI.s16, AppUI.s8, AppUI.s16, AppUI.s8),
            child: Text('Toque en el mapa el lugar exacto. Puede arrastrar y acercar.',
                style: AppUI.bodySoft),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _picked,
                initialZoom: widget.initial != null ? 15 : 6,
                onTap: (_, point) => setState(() {
                  _picked = point;
                  _hasPick = true;
                }),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'store.vendia.app',
                ),
                if (_hasPick)
                  MarkerLayer(markers: [
                    Marker(
                      point: _picked,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.location_on_rounded,
                          color: AppTheme.error, size: 40),
                    ),
                  ]),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppUI.s16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _hasPick
                      ? () => Navigator.of(context).pop(_picked)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppUI.radiusSm)),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(_hasPick ? 'Confirmar ubicación' : 'Toque el mapa primero'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
