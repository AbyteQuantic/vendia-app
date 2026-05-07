import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/receipt_builder.dart';

/// Returns true if [needle] appears anywhere as a contiguous subsequence
/// inside [haystack]. Plain O(n*m) — fine for short receipt streams.
bool _containsSubsequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  if (haystack.length < needle.length) return false;
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    bool match = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

/// ASCII byte sequence for [s].
List<int> _ascii(String s) => s.codeUnits;

void main() {
  // CapabilityProfile.load() reads a JSON asset bundled with
  // esc_pos_utils_plus, so the Flutter services binding must be
  // initialised before any builder.build() is invoked.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The drawer kick the builder emits literally — pin 2, 25ms on, 250ms off.
  const drawerKick = [27, 112, 0, 25, 250];

  // ESC/POS full-cut command produced by Generator.cut() in
  // esc_pos_utils_plus 2.0.4: GS 'V' '0' = [29, 86, 48].
  const fullCut = [29, 86, 48];

  // Default fixture: a small but realistic 2-line sale.
  const tenant = ReceiptTenantInfo(
    businessName: 'BURRITOS BRYAN',
    nit: '900123456-7',
    address: 'Cra 7 #1-23',
    phone: '3001234567',
  );
  const lines = [
    ReceiptLine(name: 'Empanada', quantity: 2, unitPrice: 500),
    ReceiptLine(name: 'Gaseosa', quantity: 1, unitPrice: 3000),
  ];

  test('drawer kick present when openDrawer=true', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
      openDrawer: true,
    );

    final out = await builder.build();

    expect(_containsSubsequence(out, drawerKick), isTrue,
        reason: 'expected drawer-kick bytes [27,112,0,25,250] in output');
  });

  test('drawer kick absent when openDrawer=false', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
      openDrawer: false,
    );

    final out = await builder.build();

    expect(_containsSubsequence(out, drawerKick), isFalse,
        reason: 'drawer-kick must NOT appear when openDrawer=false');
  });

  test('full cut command present when cutPaper=true', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
      cutPaper: true,
    );

    final out = await builder.build();

    expect(_containsSubsequence(out, fullCut), isTrue,
        reason: 'expected GS V 0 cut command [29,86,48] when cutPaper=true');
  });

  test('full cut command absent when cutPaper=false', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
      cutPaper: false,
    );

    final out = await builder.build();

    expect(_containsSubsequence(out, fullCut), isFalse,
        reason: 'cut command must NOT appear when cutPaper=false');
  });

  test('businessName is encoded into the output as ASCII', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
    );

    final out = await builder.build();

    expect(_containsSubsequence(out, _ascii('BURRITOS BRYAN')), isTrue,
        reason: 'business name must appear as ASCII bytes in receipt');
  });

  test('qty=2 unitPrice=500 produces \$1.000 subtotal in stream', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: const [
        ReceiptLine(name: 'Empanada', quantity: 2, unitPrice: 500),
      ],
      total: 1000,
      paymentMethod: 'efectivo',
    );

    final out = await builder.build();

    expect(_containsSubsequence(out, _ascii('\$1.000')), isTrue,
        reason: 'subtotal 1000 must be formatted as \$1.000 with thousands dot');
  });

  test('tenant without logoBytes builds without throwing', () async {
    final builder = ReceiptBuilder(
      tenant: const ReceiptTenantInfo(businessName: 'NO LOGO STORE'),
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
    );

    final out = await builder.build();

    expect(out, isNotEmpty);
    expect(_containsSubsequence(out, _ascii('NO LOGO STORE')), isTrue);
  });

  test('tenant with garbage logoBytes degrades gracefully', () async {
    // Random bytes — clearly not a valid PNG/JPEG. The builder must catch
    // the decode failure and emit a text-only header.
    final garbage = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 31 + 7) & 0xFF));

    final builder = ReceiptBuilder(
      tenant: ReceiptTenantInfo(
        businessName: 'GARBAGE LOGO',
        logoBytes: garbage,
      ),
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
    );

    // Must not throw — the whole point of the graceful-degradation path.
    final out = await builder.build();

    expect(out, isNotEmpty);
    expect(_containsSubsequence(out, _ascii('GARBAGE LOGO')), isTrue,
        reason:
            'text header must still print even when logo bytes are invalid');
  });

  test('payment method is upper-cased in the receipt body', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'nequi',
    );

    final out = await builder.build();

    expect(_containsSubsequence(out, _ascii('Pago: NEQUI')), isTrue,
        reason: 'paymentMethod argument must be upper-cased on the ticket');
  });

  test('mm80 paper size still produces a valid stream', () async {
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
      paperSize: PaperSize.mm80,
    );

    final out = await builder.build();

    expect(out, isNotEmpty);
    expect(_containsSubsequence(out, _ascii('TOTAL')), isTrue);
  });
}
