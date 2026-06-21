// Spec: specs/072-captura-ubicacion-gps-osm/spec.md
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../theme/app_theme.dart';
import '../theme/app_ui.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Botón reusable "Usar mi ubicación actual" (Spec 072): captura GPS, deriva la
/// ciudad (geocoder nativo) y la persiste vía PATCH /store/location. Llama
/// [onDone] al terminar para que la pantalla recargue. Tolera permiso denegado.
class UseMyLocationButton extends StatefulWidget {
  final VoidCallback onDone;
  final ApiService? api;
  const UseMyLocationButton({super.key, required this.onDone, this.api});

  @override
  State<UseMyLocationButton> createState() => _UseMyLocationButtonState();
}

class _UseMyLocationButtonState extends State<UseMyLocationButton> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _snack('Permiso de ubicación denegado. Actívelo para ver proveedores cerca.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      String city = '';
      try {
        final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (places.isNotEmpty) city = places.first.locality ?? '';
      } catch (_) {}
      await _api.updateStoreLocation(
          latitude: pos.latitude, longitude: pos.longitude, accuracy: pos.accuracy, city: city);
      if (!mounted) return;
      _snack(city.isNotEmpty ? 'Ubicación guardada · $city' : 'Ubicación guardada', ok: true);
      widget.onDone();
    } catch (_) {
      _snack('No pudimos obtener su ubicación. Intente de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: ok ? AppTheme.success : AppTheme.error));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        key: const Key('btn_fix_location_inline'),
        onPressed: _busy ? null : _capture,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.my_location_rounded, size: 20),
        label: const Text('Usar mi ubicación actual'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm)),
        ),
      ),
    );
  }
}
