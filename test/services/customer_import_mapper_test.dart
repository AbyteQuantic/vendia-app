// Spec: specs/026-importador-clientes/spec.md
//
// Tests for CustomerImportMapper — proposeMapping + validateRow.
// Cases: T-11 (auto-mapping) + edge cases per spec §9.

import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/customer_import_mapper.dart';

void main() {
  group('CustomerImportMapper.proposeMapping', () {
    // ── Nombre / name ──────────────────────────────────────────────
    test('"Nombre" maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['Nombre']);
      expect(m[0], equals('name'));
    });

    test('"NOMBRE" (uppercase) maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['NOMBRE']);
      expect(m[0], equals('name'));
    });

    test('"Cliente" maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['Cliente']);
      expect(m[0], equals('name'));
    });

    test('"nombre del cliente" maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['nombre del cliente']);
      expect(m[0], equals('name'));
    });

    test('"razón social" (with tilde) maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['razón social']);
      expect(m[0], equals('name'));
    });

    test('"razon social" (without tilde) maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['razon social']);
      expect(m[0], equals('name'));
    });

    test('"full name" maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['full name']);
      expect(m[0], equals('name'));
    });

    test('"nombres" maps to name', () {
      final m = CustomerImportMapper.proposeMapping(['nombres']);
      expect(m[0], equals('name'));
    });

    // ── Teléfono / phone ───────────────────────────────────────────
    test('"Celular" maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['Celular']);
      expect(m[0], equals('phone'));
    });

    test('"Teléfono" (with tilde) maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['Teléfono']);
      expect(m[0], equals('phone'));
    });

    test('"telefono" (without tilde) maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['telefono']);
      expect(m[0], equals('phone'));
    });

    test('"celular" lowercase maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['celular']);
      expect(m[0], equals('phone'));
    });

    test('"Whatsapp" maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['Whatsapp']);
      expect(m[0], equals('phone'));
    });

    test('"Movil" maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['Movil']);
      expect(m[0], equals('phone'));
    });

    test('"Móvil" (with tilde) maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['Móvil']);
      expect(m[0], equals('phone'));
    });

    test('"numero" maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['numero']);
      expect(m[0], equals('phone'));
    });

    test('"número" (with tilde) maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['número']);
      expect(m[0], equals('phone'));
    });

    test('"tel" maps to phone', () {
      final m = CustomerImportMapper.proposeMapping(['tel']);
      expect(m[0], equals('phone'));
    });

    // ── Correo / email ─────────────────────────────────────────────
    test('"email" maps to email', () {
      final m = CustomerImportMapper.proposeMapping(['email']);
      expect(m[0], equals('email'));
    });

    test('"Correo" maps to email', () {
      final m = CustomerImportMapper.proposeMapping(['Correo']);
      expect(m[0], equals('email'));
    });

    test('"Correo Electrónico" (with tilde) maps to email', () {
      final m = CustomerImportMapper.proposeMapping(['Correo Electrónico']);
      expect(m[0], equals('email'));
    });

    test('"correo electronico" (without tilde) maps to email', () {
      final m = CustomerImportMapper.proposeMapping(['correo electronico']);
      expect(m[0], equals('email'));
    });

    test('"Mail" maps to email', () {
      final m = CustomerImportMapper.proposeMapping(['Mail']);
      expect(m[0], equals('email'));
    });

    test('"e-mail" maps to email', () {
      final m = CustomerImportMapper.proposeMapping(['e-mail']);
      expect(m[0], equals('email'));
    });

    // ── Notas / notes ──────────────────────────────────────────────
    test('"Notas" maps to notes', () {
      final m = CustomerImportMapper.proposeMapping(['Notas']);
      expect(m[0], equals('notes'));
    });

    test('"Observaciones" maps to notes', () {
      final m = CustomerImportMapper.proposeMapping(['Observaciones']);
      expect(m[0], equals('notes'));
    });

    test('"comentarios" maps to notes', () {
      final m = CustomerImportMapper.proposeMapping(['comentarios']);
      expect(m[0], equals('notes'));
    });

    test('"obs" maps to notes', () {
      final m = CustomerImportMapper.proposeMapping(['obs']);
      expect(m[0], equals('notes'));
    });

    test('"nota" maps to notes', () {
      final m = CustomerImportMapper.proposeMapping(['nota']);
      expect(m[0], equals('notes'));
    });

    // ── Unknown / ignored ─────────────────────────────────────────
    test('"SKU" (unknown) returns null', () {
      final m = CustomerImportMapper.proposeMapping(['SKU']);
      expect(m[0], isNull);
    });

    test('"Precio" (unknown) returns null', () {
      final m = CustomerImportMapper.proposeMapping(['Precio']);
      expect(m[0], isNull);
    });

    // ── Multi-column scenarios ─────────────────────────────────────
    test('typical Colombian Excel: Nombre, Celular, Correo, Notas', () {
      final m = CustomerImportMapper.proposeMapping(
          ['Nombre', 'Celular', 'Correo', 'Notas']);
      expect(m[0], equals('name'));
      expect(m[1], equals('phone'));
      expect(m[2], equals('email'));
      expect(m[3], equals('notes'));
    });

    test('headers with mixed case and spaces', () {
      final m = CustomerImportMapper.proposeMapping(
          ['  Nombre  ', ' CELULAR ', 'CORREO ELECTRÓNICO']);
      expect(m[0], equals('name'));
      expect(m[1], equals('phone'));
      expect(m[2], equals('email'));
    });

    test('duplicate mapping: first header wins for same target', () {
      // Both "Nombre" and "Cliente" map to name — first index wins
      final m = CustomerImportMapper.proposeMapping(['Nombre', 'Cliente']);
      expect(m[0], equals('name'));
      // Second one should be null (already claimed)
      expect(m[1], isNull);
    });

    test('empty headers list returns empty map', () {
      final m = CustomerImportMapper.proposeMapping([]);
      expect(m, isEmpty);
    });
  });

  group('CustomerImportMapper.validateRow', () {
    test('valid row with name, phone, email, notes passes', () {
      final result = CustomerImportMapper.validateRow({
        'name': 'Juan Pérez',
        'phone': '3001234567',
        'email': 'juan@x.co',
        'notes': '',
      });
      expect(result.ok, isTrue);
    });

    test('valid row with name only passes', () {
      final result = CustomerImportMapper.validateRow({'name': 'Pedro'});
      expect(result.ok, isTrue);
    });

    test('empty name fails with "nombre vacío"', () {
      final result = CustomerImportMapper.validateRow({'name': ''});
      expect(result.ok, isFalse);
      expect(result.reason, contains('vacío'));
    });

    test('null name fails with "nombre vacío"', () {
      final result = CustomerImportMapper.validateRow({'name': null});
      expect(result.ok, isFalse);
      expect(result.reason, contains('vacío'));
    });

    test('name with only whitespace fails with "nombre vacío"', () {
      final result = CustomerImportMapper.validateRow({'name': '   '});
      expect(result.ok, isFalse);
      expect(result.reason, contains('vacío'));
    });

    test('name with 1 char fails with "muy corto"', () {
      final result = CustomerImportMapper.validateRow({'name': 'A'});
      expect(result.ok, isFalse);
      expect(result.reason, contains('corto'));
    });

    test('name with 2 chars passes', () {
      final result = CustomerImportMapper.validateRow({'name': 'AB'});
      expect(result.ok, isTrue);
    });

    test('name with leading/trailing spaces is trimmed and validated', () {
      // "  A  " trims to "A" → 1 char → too short
      final result = CustomerImportMapper.validateRow({'name': '  A  '});
      expect(result.ok, isFalse);
    });

    test('completely empty row (no name key) fails', () {
      final result = CustomerImportMapper.validateRow({});
      expect(result.ok, isFalse);
    });

    test('valid name with tabs/newlines in it trims correctly', () {
      // "  Pedro\n" trims to "Pedro" → 5 chars → ok
      final result = CustomerImportMapper.validateRow({'name': '  Pedro\n'});
      expect(result.ok, isTrue);
    });
  });

  group('CustomerImportMapper.normalizeHeader (strip accents)', () {
    test('"Teléfono" normalizes same as "Telefono"', () {
      final a =
          CustomerImportMapper.proposeMapping(['Teléfono'])[0];
      final b = CustomerImportMapper.proposeMapping(['Telefono'])[0];
      expect(a, equals(b));
      expect(a, equals('phone'));
    });

    test('"Correo Electrónico" normalizes same as "Correo Electronico"', () {
      final a = CustomerImportMapper.proposeMapping(['Correo Electrónico'])[0];
      final b =
          CustomerImportMapper.proposeMapping(['Correo Electronico'])[0];
      expect(a, equals(b));
      expect(a, equals('email'));
    });
  });
}
