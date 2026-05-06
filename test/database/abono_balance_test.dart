import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Abono balance math', () {
    test('100k tab with 40k abono → pending 60k', () {
      const grossTotal = 100000.0;
      const abonosTotal = 40000.0;
      final raw = grossTotal - abonosTotal;
      final pending = raw < 0 ? 0.0 : raw;
      expect(pending, 60000.0);
    });

    test('multiple abonos accumulate correctly', () {
      const grossTotal = 100000.0;
      var abonosTotal = 0.0;
      abonosTotal += 30000.0;
      abonosTotal += 20000.0;
      abonosTotal += 10000.0;
      final raw = grossTotal - abonosTotal;
      final pending = raw < 0 ? 0.0 : raw;
      expect(pending, 40000.0);
      expect(abonosTotal, 60000.0);
    });

    test('overpayment clamps pending to 0 (never negative)', () {
      const grossTotal = 100000.0;
      const abonosTotal = 150000.0;
      final raw = grossTotal - abonosTotal;
      final pending = raw < 0 ? 0.0 : raw;
      expect(pending, 0.0);
    });
  });
}
