// Spec: specs/086-branding-estacional/spec.md
//
// Estado de branding estacional para la app. seed() en bootstrap (sin notify);
// refresh() revalida en segundo plano y notifica si cambió. activeAccent
// centraliza el override (o el token de marca) en UN solo lugar.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/seasonal_branding.dart';
import '../theme/app_theme.dart';
import 'seasonal_branding_service.dart';

/// Lectura DEFENSIVA del branding activo: si el provider no está montado
/// (p. ej. en un widget test que monta una pantalla suelta), cae a marca
/// normal en vez de lanzar ProviderNotFoundException. Registra dependencia
/// (rebuild al cambiar la temporada) cuando sí existe.
SeasonalBranding watchSeasonalBranding(BuildContext context) {
  try {
    return Provider.of<SeasonalBrandingController>(context).branding;
  } catch (_) {
    return const SeasonalBranding.normal();
  }
}

class SeasonalBrandingController extends ChangeNotifier {
  SeasonalBrandingController({SeasonalBrandingService? service})
      : _service = service ?? SeasonalBrandingService();

  final SeasonalBrandingService _service;
  SeasonalBranding _branding = const SeasonalBranding.normal();

  SeasonalBranding get branding => _branding;
  bool get active => _branding.active;

  /// Color de acento efectivo: override de temporada si activo y válido, si no
  /// el token de marca. Único punto que decide override vs token (DESIGN_SYSTEM).
  Color get activeAccent =>
      _branding.active ? (_branding.accentColor ?? AppTheme.accent) : AppTheme.accent;

  /// Bootstrap: fija el branding cacheado SIN notificar (antes del primer frame).
  void seed(SeasonalBranding b) {
    _branding = b;
  }

  /// Revalida con el servidor; notifica solo si cambió (evita rebuild inútil).
  Future<void> refresh() async {
    final next = await _service.refresh();
    if (next.key != _branding.key || next.active != _branding.active) {
      _branding = next;
      notifyListeners();
    } else {
      _branding = next; // mismos datos visibles, actualiza referencia silenciosa
    }
  }
}
