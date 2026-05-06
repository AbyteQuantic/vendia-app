import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Abono prefill source priority', () {
    /// Extracts and resolves the prefill amount from stream-based
    /// pendingBalance and fallback _data['remaining_balance'].
    ///
    /// Priority:
    /// 1. Stream pendingBalance (if > 0) — ISAR is authoritative
    /// 2. _data['remaining_balance'] (if pendingBalance <= 0)
    /// 3. 0 (if both absent)
    double resolveRemaining({
      double? streamPendingBalance,
      num? dataRemainingBalance,
    }) {
      double prefill = 0;
      if (streamPendingBalance != null && streamPendingBalance > 0) {
        prefill = streamPendingBalance;
      }
      if (prefill <= 0) {
        prefill = dataRemainingBalance?.toDouble() ?? 0;
      }
      return prefill;
    }

    test('stream pendingBalance is preferred when positive', () {
      expect(
          resolveRemaining(
              streamPendingBalance: 50000, dataRemainingBalance: 30000),
          50000);
    });

    test('falls back to _data when stream tab is null/zero', () {
      expect(
          resolveRemaining(
              streamPendingBalance: 0, dataRemainingBalance: 30000),
          30000);
    });

    test('returns 0 when both sources are absent', () {
      expect(resolveRemaining(), 0);
    });

    test('zero pendingBalance with non-positive _data → 0 (paid in full)', () {
      expect(
          resolveRemaining(
              streamPendingBalance: 0, dataRemainingBalance: 0),
          0);
    });

    test('null stream + null _data → 0 (no source available)', () {
      expect(
          resolveRemaining(
              streamPendingBalance: null, dataRemainingBalance: null),
          0);
    });

    test('stream null but _data positive → uses _data', () {
      expect(
          resolveRemaining(
              streamPendingBalance: null, dataRemainingBalance: 25000),
          25000);
    });

    test('stream zero with large _data → uses _data (paid in full locally)', () {
      expect(
          resolveRemaining(
              streamPendingBalance: 0, dataRemainingBalance: 99999),
          99999);
    });
  });
}
