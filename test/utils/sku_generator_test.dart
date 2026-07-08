// Spec: specs/100-completar-skus-inventario/spec.md (T-10)
//
// Generador de SKU interno extraído a utilidad: formato
// VND-<PRES3>-<AAA>-<4 dígitos>, presentaciones mapeadas, nombres cortos
// rellenan con X, y dos llamadas seguidas NO repiten el sufijo (semilla
// aleatoria — millis%10000 producía casi-consecutivos en ráfaga).

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/sku_generator.dart';

void main() {
  group('generateSku — formato', () {
    test('produce VND-<PRES>-<AAA>-<dddd>', () {
      final sku = generateSku(name: 'Empanada', presentation: 'Unidad');
      expect(sku, matches(RegExp(r'^VND-UNI-EMP-\d{4}$')));
    });

    test('nombre con espacios y tildes usa solo letras A-Z', () {
      final sku = generateSku(name: 'agua manantial', presentation: 'Botella');
      expect(sku, matches(RegExp(r'^VND-BOT-AGU-\d{4}$')));
    });

    test('nombre corto rellena con X hasta 3 letras', () {
      final sku = generateSku(name: 'Aj', presentation: 'Bolsa');
      expect(sku, matches(RegExp(r'^VND-BLS-AJX-\d{4}$')));
    });

    test('nombre vacío rellena con XXX', () {
      final sku = generateSku(name: '', presentation: 'Caja');
      expect(sku, matches(RegExp(r'^VND-CAJ-XXX-\d{4}$')));
    });
  });

  group('generateSku — presentaciones', () {
    const cases = {
      'Botella': 'BOT',
      'Lata': 'LAT',
      'Bolsa': 'BLS',
      'Caja': 'CAJ',
      'Frasco': 'FRA',
      'Paquete': 'PAQ',
      'Unidad': 'UNI',
      'Sobre': 'SOB',
      'Otro': 'OTR',
    };

    for (final entry in cases.entries) {
      test('${entry.key} → ${entry.value}', () {
        final sku = generateSku(name: 'Producto', presentation: entry.key);
        expect(sku, startsWith('VND-${entry.value}-PRO-'));
      });
    }

    test('presentación en minúsculas también mapea (case-insensitive)', () {
      final sku = generateSku(name: 'Producto', presentation: 'sobre');
      expect(sku, startsWith('VND-SOB-PRO-'));
    });

    test('presentación desconocida cae a GEN', () {
      final sku = generateSku(name: 'Producto', presentation: 'Tonel');
      expect(sku, startsWith('VND-GEN-PRO-'));
    });
  });

  group('generateSku — sufijo aleatorio', () {
    test('llamadas seguidas no repiten todas el mismo sufijo', () {
      // Con la semilla vieja (millis%10000) 20 llamadas en el mismo
      // milisegundo devolvían TODAS el mismo sufijo. Con Random.secure()
      // la probabilidad de que 20 coincidan es despreciable (<1e-70).
      final suffixes = {
        for (var i = 0; i < 20; i++)
          generateSku(name: 'Empanada', presentation: 'Unidad').split('-').last,
      };
      expect(suffixes.length, greaterThan(1));
    });

    test('el sufijo siempre tiene 4 dígitos (con ceros a la izquierda)', () {
      for (var i = 0; i < 50; i++) {
        final suffix =
            generateSku(name: 'Pan', presentation: 'Unidad').split('-').last;
        expect(suffix, matches(RegExp(r'^\d{4}$')));
      }
    });
  });
}
