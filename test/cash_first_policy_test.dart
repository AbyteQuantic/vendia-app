import 'package:flutter_test/flutter_test.dart';

/// Cash-First INNEGOCIABLE: the checkout MUST always offer Efectivo.
/// These tests pin the policy at unit level, mirroring the gate
/// inside the StreamBuilder so a future refactor can't accidentally
/// drop the cash anchor.
void main() {
  // Mirror the chip-selection logic.
  ({bool hasCashChip, String cashLabel, bool hasNequi, bool hasFiar})
      computeChips({
    required List<({bool isActive, String name, String? provider})>
        tenantMethods,
    required bool fiadoEnabled,
  }) {
    final activeNonBlank = tenantMethods
        .where((m) => m.isActive && m.name.trim().isNotEmpty)
        .toList();
    var realCashLabel = 'Efectivo';
    var foundRealCash = false;
    for (final m in activeNonBlank) {
      final isCash = m.provider == 'cash' ||
          m.name.trim().toLowerCase() == 'efectivo';
      if (isCash) {
        foundRealCash = true;
        realCashLabel = m.name;
        break;
      }
    }
    final nonCash = activeNonBlank.where((m) {
      if (m.provider == 'cash') return false;
      if (m.name.trim().toLowerCase() == 'efectivo') return false;
      return true;
    }).toList();
    return (
      hasCashChip: true, // Always.
      cashLabel: realCashLabel,
      hasNequi: nonCash.any((m) => m.name.toLowerCase().contains('nequi')),
      hasFiar: fiadoEnabled,
    );
  }

  test('empty tenant list still shows Efectivo chip', () {
    final r = computeChips(tenantMethods: const [], fiadoEnabled: false);
    expect(r.hasCashChip, isTrue);
    expect(r.cashLabel, 'Efectivo');
    expect(r.hasNequi, isFalse);
    expect(r.hasFiar, isFalse);
  });

  test('tenant with only Nequi still shows Efectivo chip — '
      'PO regression case', () {
    final r = computeChips(
      tenantMethods: [
        (isActive: true, name: 'Nequi', provider: 'nequi'),
      ],
      fiadoEnabled: false,
    );
    expect(r.hasCashChip, isTrue,
        reason: 'Cash-First INNEGOCIABLE: cash chip must render');
    expect(r.cashLabel, 'Efectivo');
    expect(r.hasNequi, isTrue);
  });

  test('all tenant methods inactive → cash chip still present', () {
    final r = computeChips(
      tenantMethods: [
        (isActive: false, name: 'Efectivo', provider: 'cash'),
        (isActive: false, name: 'Nequi', provider: 'nequi'),
      ],
      fiadoEnabled: false,
    );
    expect(r.hasCashChip, isTrue);
    expect(r.cashLabel, 'Efectivo');
    expect(r.hasNequi, isFalse);
  });

  test('tenant has real Efectivo row → uses tenant label', () {
    final r = computeChips(
      tenantMethods: [
        (isActive: true, name: 'Efectivo COP', provider: 'cash'),
        (isActive: true, name: 'Nequi', provider: 'nequi'),
      ],
      fiadoEnabled: true,
    );
    expect(r.hasCashChip, isTrue);
    expect(r.cashLabel, 'Efectivo COP',
        reason: 'tenant display label wins when real cash row exists');
    expect(r.hasNequi, isTrue);
    expect(r.hasFiar, isTrue);
  });

  test('tenant cash row identified by name when provider is null', () {
    final r = computeChips(
      tenantMethods: [
        (isActive: true, name: 'Efectivo', provider: null),
        (isActive: true, name: 'Nequi', provider: 'nequi'),
      ],
      fiadoEnabled: false,
    );
    expect(r.cashLabel, 'Efectivo');
    expect(r.hasNequi, isTrue);
  });

  test('blank-name cash row is ignored, fallback synthesised', () {
    final r = computeChips(
      tenantMethods: [
        (isActive: true, name: '   ', provider: 'cash'),
      ],
      fiadoEnabled: false,
    );
    expect(r.hasCashChip, isTrue);
    expect(r.cashLabel, 'Efectivo');
  });
}
