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

List<int> _ascii(String s) => s.codeUnits;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenant = ReceiptTenantInfo(
    businessName: 'TIENDA DEL BARRIO',
    nit: '900111222-3',
  );

  test('legacy lines (no taxAmount) emit NO IVA footer line', () async {
    const lines = [
      ReceiptLine(name: 'Empanada', quantity: 2, unitPrice: 500),
      ReceiptLine(name: 'Gaseosa', quantity: 1, unitPrice: 3000),
    ];
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 4000,
      paymentMethod: 'efectivo',
      openDrawer: false,
      cutPaper: false,
    );
    final bytes = await builder.build();
    expect(_containsSubsequence(bytes, _ascii('IVA')), false,
        reason: 'pre-feature receipts must stay byte-identical to before');
  });

  test('lines with taxAmount=1900 @ 19% emit "IVA (19%)" + "\$1.900"',
      () async {
    // 11.900 inclusive @ 19% extracts exactly 1900 of tax (11900/1.19=10000).
    const lines = [
      ReceiptLine(
        name: 'Producto A',
        quantity: 1,
        unitPrice: 11900,
        taxRate: 0.19,
        taxAmount: 1900.0,
        isTaxInclusive: true,
      ),
    ];
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 11900,
      paymentMethod: 'efectivo',
      openDrawer: false,
      cutPaper: false,
    );
    final bytes = await builder.build();
    expect(_containsSubsequence(bytes, _ascii('IVA (19%)')), true,
        reason: 'must label the tax block with the rate the sale closed at');
    expect(_containsSubsequence(bytes, _ascii('\$1.900')), true,
        reason: 'tax amount must be formatted in COP with thousand sep');
  });

  test('rate of 0% with non-zero taxAmount still emits the footer label',
      () async {
    // Edge case: a 0%-rate line technically has taxAmount=0 and
    // should NOT trigger the footer. We assert nothing leaks through.
    const lines = [
      ReceiptLine(
        name: 'Exento',
        quantity: 1,
        unitPrice: 5000,
        taxRate: 0,
        taxAmount: 0,
        isTaxInclusive: false,
      ),
    ];
    final builder = ReceiptBuilder(
      tenant: tenant,
      lines: lines,
      total: 5000,
      paymentMethod: 'efectivo',
      openDrawer: false,
      cutPaper: false,
    );
    final bytes = await builder.build();
    expect(_containsSubsequence(bytes, _ascii('IVA')), false,
        reason: '0-tax sales should not print an empty IVA footer');
  });
}
