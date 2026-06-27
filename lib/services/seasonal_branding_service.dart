// Spec: specs/086-branding-estacional/spec.md
//
// Servicio de branding estacional — offline-first, espejo de CatalogService:
// cachea la última temporada conocida (SharedPreferences, sobrevive refresh PWA),
// usa ETag para no re-descargar, y ante CUALQUIER fallo cae a la cache o a la
// marca normal. NUNCA lanza (no debe romper el arranque ni el splash pre-login).

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/seasonal_branding.dart';
import 'api_service.dart';
import 'auth_service.dart';

typedef BrandingFetcher = Future<
    ({Map<String, dynamic>? data, String etag, bool notModified})> Function(
    {String? etag});

class SeasonalBrandingService {
  SeasonalBrandingService({BrandingFetcher? fetcher})
      : _fetch = fetcher ??
            ((({String? etag}) =>
                ApiService(AuthService()).fetchSeasonalBranding(etag: etag)));

  final BrandingFetcher _fetch;

  static const _kJson = 'vendia_branding_json';
  static const _kEtag = 'vendia_branding_etag';

  /// Última temporada cacheada, o marca normal si nunca se obtuvo / corrupta.
  Future<SeasonalBranding> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kJson);
      if (raw == null || raw.isEmpty) return const SeasonalBranding.normal();
      return SeasonalBranding.fromJson(jsonDecode(raw));
    } catch (_) {
      return const SeasonalBranding.normal();
    }
  }

  /// Revalida con el servidor (ETag). 304/sin red → cache. Persiste lo nuevo.
  /// Nunca lanza.
  Future<SeasonalBranding> refresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedEtag = prefs.getString(_kEtag);
      final res = await _fetch(etag: storedEtag);
      if (res.notModified || res.data == null) {
        return cached();
      }
      final branding = SeasonalBranding.fromJson(res.data);
      await prefs.setString(_kJson, jsonEncode(branding.toJson()));
      if (res.etag.isNotEmpty) {
        await prefs.setString(_kEtag, res.etag);
      }
      return branding;
    } catch (_) {
      return cached(); // offline / error → último conocido
    }
  }
}
