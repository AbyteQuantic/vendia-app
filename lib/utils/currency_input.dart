import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Currency utilities for COP (Colombian Pesos) input fields.
///
/// Display in this app is "12.345" (no symbol, no decimals — the
/// surrounding UI shows the '\$' prefix). Storage always returns a
/// double in pesos.
class CurrencyUtils {
  CurrencyUtils._();

  static final NumberFormat _format = NumberFormat('#,###', 'es_CO');

  /// Format an integer amount of pesos as "12.345".
  /// Returns empty string for null / zero so the input does not show
  /// a leading "0" that the cashier has to delete.
  static String formatInt(int amount) {
    if (amount <= 0) return '';
    return _format.format(amount);
  }

  /// Parse any user-typed currency string back to a double in pesos.
  /// Strips '\$', dots, commas, NBSP, regular spaces. Returns 0 for
  /// empty or non-numeric input. NEVER throws.
  static double parseToDouble(String? raw) {
    if (raw == null) return 0;
    final cleaned = raw
        .replaceAll('\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '')
        .replaceAll(' ', '') // non-breaking space
        .trim();
    if (cleaned.isEmpty) return 0;
    return double.tryParse(cleaned) ?? 0;
  }
}

/// TextInputFormatter that keeps the input as digits-only and renders
/// thousand separators in es_CO style ("12.345"). Cursor is parked at
/// the end after every edit — acceptable for cash entry where the
/// cashier types left-to-right.
class CurrencyInputFormatter extends TextInputFormatter {
  const CurrencyInputFormatter();

  static final NumberFormat _format = NumberFormat('#,###', 'es_CO');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    // Strip everything except digits.
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final n = int.tryParse(digits);
    if (n == null) return oldValue;
    final formatted = _format.format(n);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
