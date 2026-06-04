// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
//
// Servicio del catálogo dinámico (F041) — offline-first (Art. II):
//   - cachea el último catálogo conocido en SharedPreferences (persiste en
//     web vía localStorage y en móvil),
//   - usa ETag para no re-descargar si no cambió (D3),
//   - si no hay red, sirve la cache; si nunca la obtuvo, devuelve null y el
//     dashboard usa su bundle compilado por defecto.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog/catalog_models.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Firma del fetch (inyectable en tests).
typedef CatalogFetcher = Future<
    ({Map<String, dynamic>? data, String etag, bool notModified})> Function(
    {String? etag});

class CatalogService {
  CatalogService({CatalogFetcher? fetcher})
      : _fetch = fetcher ??
            ((({String? etag}) =>
                ApiService(AuthService()).fetchBusinessCatalog(etag: etag)));

  final CatalogFetcher _fetch;

  static const _kJson = 'vendia_catalog_json';
  static const _kEtag = 'vendia_catalog_etag';

  /// Catálogo cacheado (último conocido), o null si nunca se obtuvo.
  Future<Catalog?> cached() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kJson);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Catalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // cache corrupta → como si no hubiera
    }
  }

  /// Trae el catálogo del backend usando el ETag guardado. Si no cambió
  /// (304), devuelve la cache. Si falla la red, devuelve la cache (offline).
  /// Persiste el resultado nuevo. Nunca lanza: el dashboard no debe romperse
  /// por un fallo de catálogo.
  Future<Catalog?> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final storedEtag = prefs.getString(_kEtag);
    try {
      final res = await _fetch(etag: storedEtag);
      if (res.notModified || res.data == null) {
        return cached();
      }
      final catalog = Catalog.fromJson(res.data!);
      // Solo persistimos un catálogo no vacío (evita pisar la cache buena
      // con una respuesta degradada).
      if (!catalog.isEmpty) {
        await prefs.setString(_kJson, jsonEncode(catalog.toJson()));
        if (res.etag.isNotEmpty) {
          await prefs.setString(_kEtag, res.etag);
        }
      }
      return catalog;
    } catch (_) {
      return cached(); // offline / error → último catálogo conocido
    }
  }
}
