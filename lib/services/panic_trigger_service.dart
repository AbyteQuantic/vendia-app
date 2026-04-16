import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Triggers the cloud panic alert with optional live GPS.
/// Called from PanicButton widget or hardware volume key shortcut.
class PanicTriggerService {
  static Future<void> trigger() async {
    HapticFeedback.heavyImpact();

    double lat = 0, lng = 0;

    // Try to capture live GPS (best effort, don't block if fails)
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 5));
        lat = pos.latitude;
        lng = pos.longitude;
      }
    } catch (_) {} // GPS may fail — proceed without it

    try {
      final api = ApiService(AuthService());
      await api.triggerPanic(liveLatitude: lat, liveLongitude: lng);
    } catch (_) {} // Cloud trigger is fire-and-forget

    HapticFeedback.heavyImpact();
  }
}
