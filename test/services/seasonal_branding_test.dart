// Spec: specs/086-branding-estacional/spec.md
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/models/seasonal_branding.dart';
import 'package:vendia_pos/services/seasonal_branding_service.dart';

void main() {
  group('SeasonalBranding.fromJson (fail-safe)', () {
    test('basura / null → marca normal sin lanzar', () {
      expect(SeasonalBranding.fromJson('x').active, isFalse);
      expect(SeasonalBranding.fromJson(null).active, isFalse);
      expect(const SeasonalBranding.normal().active, isFalse);
    });

    test('temporada activa parsea overrides anidados', () {
      final b = SeasonalBranding.fromJson({
        'active': true,
        'key': 'navidad_2026',
        'accent_hex': '#C0392B',
        'icon_variant': 'navidad',
        'splash': {'bg_hex': '#0A2540', 'message': 'Feliz Navidad'},
        'banner': {'text': 'Felices fiestas', 'bg_hex': '#C0392B'},
      });
      expect(b.active, isTrue);
      expect(b.key, 'navidad_2026');
      expect(b.iconVariant, 'navidad');
      expect(b.accentColor, const Color(0xFFC0392B));
      expect(b.splashBg, const Color(0xFF0A2540));
      expect(b.splashMessage, 'Feliz Navidad');
      expect(b.hasBanner, isTrue);
    });

    test('hex inválido → null (cae al token de marca)', () {
      final b = SeasonalBranding.fromJson({'active': true, 'accent_hex': '#zzz'});
      expect(b.accentColor, isNull);
    });

    test('sin banner → hasBanner=false', () {
      expect(SeasonalBranding.fromJson({'active': true}).hasBanner, isFalse);
    });
  });

  group('SeasonalBrandingService (ETag/cache/offline)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('200 persiste y devuelve la temporada; 2da vez 304 → cache', () async {
      var calls = 0;
      final svc = SeasonalBrandingService(fetcher: ({String? etag}) async {
        calls++;
        if (etag == 'e1') return (data: null, etag: 'e1', notModified: true);
        return (
          data: {'active': true, 'key': 'navidad', 'icon_variant': 'navidad'},
          etag: 'e1',
          notModified: false,
        );
      });
      final first = await svc.refresh();
      expect(first.active, isTrue);
      expect(first.key, 'navidad');
      final second = await svc.refresh(); // manda If-None-Match e1 → 304
      expect(second.key, 'navidad'); // de cache
      expect(calls, 2);
    });

    test('excepción de red → cache (o normal si nunca cacheó)', () async {
      final svc = SeasonalBrandingService(
          fetcher: ({String? etag}) async => throw Exception('offline'));
      final b = await svc.refresh();
      expect(b.active, isFalse); // marca normal, no rompe
    });
  });
}
