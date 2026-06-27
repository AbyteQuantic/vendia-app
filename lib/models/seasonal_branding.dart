// Spec: specs/086-branding-estacional/spec.md
//
// Branding estacional (server-driven). Inmutable y FAIL-SAFE por construcción:
// cualquier dato faltante/corrupto → marca normal VendIA. fromJson NUNCA lanza.

import 'package:flutter/material.dart';

@immutable
class SeasonalBranding {
  final bool active;
  final String key;
  final String name;
  final String? accentHex;
  final String iconVariant;
  final String? splashBgHex;
  final String? splashImageUrl;
  final String? splashMessage;
  final String? bannerText;
  final String? bannerImageUrl;
  final String? bannerBgHex;
  final String? bannerLinkUrl;

  const SeasonalBranding({
    this.active = false,
    this.key = '',
    this.name = '',
    this.accentHex,
    this.iconVariant = 'default',
    this.splashBgHex,
    this.splashImageUrl,
    this.splashMessage,
    this.bannerText,
    this.bannerImageUrl,
    this.bannerBgHex,
    this.bannerLinkUrl,
  });

  /// Fallback canónico: marca VendIA normal (sin temporada).
  const SeasonalBranding.normal() : this();

  /// Tolerante: cualquier forma rara → normal (active:false), nunca lanza.
  factory SeasonalBranding.fromJson(Object? raw) {
    if (raw is! Map) return const SeasonalBranding.normal();
    String? s(Object? v) {
      final t = (v is String) ? v.trim() : null;
      return (t == null || t.isEmpty) ? null : t;
    }

    final splash = raw['splash'];
    final banner = raw['banner'];
    Map sp = splash is Map ? splash : const {};
    Map bn = banner is Map ? banner : const {};
    return SeasonalBranding(
      active: raw['active'] == true,
      key: s(raw['key']) ?? '',
      name: s(raw['name']) ?? '',
      accentHex: s(raw['accent_hex']),
      iconVariant: s(raw['icon_variant']) ?? 'default',
      splashBgHex: s(sp['bg_hex']),
      splashImageUrl: s(sp['image_url']),
      splashMessage: s(sp['message']),
      bannerText: s(bn['text']),
      bannerImageUrl: s(bn['image_url']),
      bannerBgHex: s(bn['bg_hex']),
      bannerLinkUrl: s(bn['link_url']),
    );
  }

  Map<String, dynamic> toJson() => {
        'active': active,
        'key': key,
        'name': name,
        'accent_hex': accentHex,
        'icon_variant': iconVariant,
        'splash': {
          'bg_hex': splashBgHex,
          'image_url': splashImageUrl,
          'message': splashMessage,
        },
        'banner': {
          'text': bannerText,
          'image_url': bannerImageUrl,
          'bg_hex': bannerBgHex,
          'link_url': bannerLinkUrl,
        },
      };

  /// Color de acento parseado del hex, o null si falta/ inválido (el consumidor
  /// cae al token de marca). Acepta #RRGGBB.
  Color? get accentColor => _parseHex(accentHex);
  Color? get splashBg => _parseHex(splashBgHex);
  Color? get bannerBg => _parseHex(bannerBgHex);

  /// ¿Hay banner que mostrar? (texto o imagen).
  bool get hasBanner => active && (bannerText != null || bannerImageUrl != null);

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    var h = hex.trim().replaceFirst('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
}
