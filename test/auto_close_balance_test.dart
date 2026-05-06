import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Auto-close gate', () {
    bool shouldAutoClose({
      required double grossTotal,
      required double abonosTotal,
      required String currentStatus,
      String? incomingStatus,
    }) {
      final pending = grossTotal - abonosTotal;
      final paidByMath = pending <= 0 && grossTotal > 0;
      final paidByStatus = incomingStatus == 'completed' ||
          incomingStatus == 'paid' ||
          incomingStatus == 'closed';
      final notYetClosed =
          currentStatus != 'completed' && currentStatus != 'paid';
      return notYetClosed && (paidByMath || paidByStatus);
    }

    test('order \$50 + abono \$50 → triggers close', () {
      expect(
          shouldAutoClose(
              grossTotal: 50, abonosTotal: 50, currentStatus: 'nuevo'),
          isTrue);
    });
    test('overpayment (\$60 abono on \$50 order) → triggers close', () {
      expect(
          shouldAutoClose(
              grossTotal: 50, abonosTotal: 60, currentStatus: 'nuevo'),
          isTrue);
    });
    test('partial payment (\$30 abono on \$50 order) → NO close', () {
      expect(
          shouldAutoClose(
              grossTotal: 50, abonosTotal: 30, currentStatus: 'nuevo'),
          isFalse);
    });
    test('already-closed tab is idempotent (no re-trigger)', () {
      expect(
          shouldAutoClose(
              grossTotal: 50, abonosTotal: 50, currentStatus: 'completed'),
          isFalse);
    });
    test('server explicitly says completed → triggers close even if math says otherwise', () {
      expect(
          shouldAutoClose(
              grossTotal: 100,
              abonosTotal: 30,
              currentStatus: 'nuevo',
              incomingStatus: 'completed'),
          isTrue);
    });
    test('empty tab (gross=0) does NOT auto-close', () {
      expect(
          shouldAutoClose(
              grossTotal: 0, abonosTotal: 0, currentStatus: 'nuevo'),
          isFalse);
    });
  });
}
