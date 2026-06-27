// Spec: specs/086-branding-estacional/spec.md
//
// Impl móvil (iOS/Android) del cambio de ícono. Usa flutter_dynamic_icon_plus.
// Idempotente + try/catch total: nunca rompe el arranque.

import 'package:flutter_dynamic_icon_plus/flutter_dynamic_icon_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'seasonal_icons.dart';

const _kApplied = 'vendia_icon_applied';

Future<void> applySeasonalIconImpl(String? variant) async {
  try {
    final want = (variant == null || variant.isEmpty) ? 'default' : variant;
    final prefs = await SharedPreferences.getInstance();
    final applied = prefs.getString(_kApplied) ?? 'default';
    if (applied == want) return; // ya aplicado → no re-disparar (evita alert iOS)

    final supported = await FlutterDynamicIconPlus.supportsAlternateIcons;
    if (!supported) return; // dispositivo sin soporte → marca normal

    // nativeIconName('default') → null = ícono primario.
    await FlutterDynamicIconPlus.setAlternateIconName(
      iconName: nativeIconName(variant),
      isSilent: true, // sin badge; el alert de iOS lo decide el sistema
    );
    await prefs.setString(_kApplied, want);
  } catch (_) {
    // Plugin no configurado / variante desconocida / error nativo → no-op.
  }
}
