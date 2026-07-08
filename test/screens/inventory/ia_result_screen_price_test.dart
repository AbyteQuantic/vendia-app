// Spec: specs/099-inventario-voz-factura-campos-separados/spec.md
//
// resolveInitialSellPrice: a dictated sell price must never be silently
// discarded and replaced by the margin-based suggestion (FR-02/AC-01) —
// but when nothing was dictated, the existing suggestion default (used
// by both invoice-sourced items, which never carry a sell price, and
// voice items where the tendero didn't mention one) must stay exactly
// as before (FR-07/AC-07).
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/inventory/ia_result_screen.dart';

void main() {
  test('a dictated sell price > 0 always wins over the margin suggestion',
      () {
    final resolved = resolveInitialSellPrice(3500, 3000, 20.0);
    expect(resolved, 3500);
  });

  test('no dictated sell price (0) falls back to suggestPrice — same as '
      'today for invoice-sourced items, which never carry sell_price', () {
    final resolved = resolveInitialSellPrice(0, 3000, 20.0);
    expect(resolved, suggestPrice(3000, 20.0).toDouble());
  });

  test('a negative dictated price is treated as "not dictated"', () {
    final resolved = resolveInitialSellPrice(-100, 3000, 20.0);
    expect(resolved, suggestPrice(3000, 20.0).toDouble());
  });
}
