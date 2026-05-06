import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/utils/currency_input.dart';

void main() {
  group('CurrencyUtils.parseToDouble', () {
    test('parses raw integer string', () {
      expect(CurrencyUtils.parseToDouble('124400'), 124400.0);
    });
    test('parses with dollar prefix and dots (es_CO display)', () {
      expect(CurrencyUtils.parseToDouble('\$124.400'), 124400.0);
    });
    test('parses with comma as thousand separator (defensive)', () {
      expect(CurrencyUtils.parseToDouble('124,400'), 124400.0);
    });
    test('parses with leading/trailing spaces', () {
      expect(CurrencyUtils.parseToDouble('  124.400  '), 124400.0);
    });
    test('returns 0 for empty string', () {
      expect(CurrencyUtils.parseToDouble(''), 0);
    });
    test('returns 0 for null', () {
      expect(CurrencyUtils.parseToDouble(null), 0);
    });
    test('returns 0 for non-numeric garbage', () {
      expect(CurrencyUtils.parseToDouble('abc!@#'), 0);
    });
    test('parses with NBSP (some keyboards inject)', () {
      expect(CurrencyUtils.parseToDouble('\$ 124.400'), 124400.0);
    });
  });

  group('CurrencyUtils.formatInt', () {
    test('formats large amount with es_CO dots', () {
      expect(CurrencyUtils.formatInt(124400), '124.400');
    });
    test('formats million-scale amount', () {
      expect(CurrencyUtils.formatInt(12345678), '12.345.678');
    });
    test('returns empty string for zero (clean input)', () {
      expect(CurrencyUtils.formatInt(0), '');
    });
    test('returns empty string for negative (defensive)', () {
      expect(CurrencyUtils.formatInt(-100), '');
    });
  });

  group('CurrencyInputFormatter', () {
    const fmt = CurrencyInputFormatter();
    TextEditingValue apply(String input) =>
        fmt.formatEditUpdate(TextEditingValue.empty,
            TextEditingValue(text: input));

    test('inserts dot every 3 digits while typing', () {
      expect(apply('12345').text, '12.345');
    });
    test('handles million-scale input', () {
      expect(apply('12345678').text, '12.345.678');
    });
    test('strips non-digits before formatting', () {
      expect(apply('1a2b3c4d5').text, '12.345');
    });
    test('returns empty for empty input (no leading 0)', () {
      expect(apply('').text, '');
    });
    test('returns empty when only non-digits typed', () {
      expect(apply('abc').text, '');
    });
    test('cursor parks at end of formatted output', () {
      final result = apply('12345');
      expect(result.selection.baseOffset, result.text.length);
    });
  });

  group('Round-trip', () {
    test('format then parse preserves the integer value', () {
      for (final n in [1, 100, 1000, 124400, 12345678]) {
        final formatted = CurrencyUtils.formatInt(n);
        final parsed = CurrencyUtils.parseToDouble(formatted);
        expect(parsed, n.toDouble(),
            reason: 'round-trip failed for $n (formatted="$formatted")');
      }
    });
  });
}
