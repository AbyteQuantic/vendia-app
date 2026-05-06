/// Validates common barcode formats using checksum algorithms.
/// Supports EAN-13, EAN-8, UPC-A, UPC-E.
class BarcodeValidator {
  BarcodeValidator._();

  /// Returns null if valid, or an error message if invalid.
  static String? validate(String code) {
    final cleaned = code.replaceAll(RegExp(r'\s'), '');
    if (cleaned.isEmpty) return null; // empty is OK (optional field)

    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return 'Solo dígitos numéricos';
    }

    switch (cleaned.length) {
      case 8:
        return _checkEan(cleaned) ? null : 'Dígito de control EAN-8 inválido';
      case 12:
        return _checkEan(cleaned) ? null : 'Dígito de control UPC-A inválido';
      case 13:
        return _checkEan(cleaned) ? null : 'Dígito de control EAN-13 inválido';
      case 14:
        return _checkEan(cleaned) ? null : 'Dígito de control ITF-14 inválido';
      default:
        // Non-standard length — accept as internal SKU
        if (cleaned.length < 4) return 'Código muy corto (mínimo 4 dígitos)';
        return null;
    }
  }

  /// EAN/UPC checksum: sum odd-position digits × 1 + even-position × 3,
  /// then check digit makes total mod 10 == 0.
  static bool _checkEan(String code) {
    int sum = 0;
    for (int i = 0; i < code.length; i++) {
      final digit = int.parse(code[i]);
      // For EAN-13: positions from right — odd × 1, even × 3
      // Simpler: from left, alternate weights depending on length
      final weight = (code.length - 1 - i).isOdd ? 1 : 3;
      sum += digit * weight;
    }
    return sum % 10 == 0;
  }

  /// Returns true if the code passes checksum validation.
  static bool isValid(String code) => validate(code) == null;

  /// Computes the check digit for a partial barcode (without check digit).
  /// E.g., pass 12 digits to get the 13th digit for EAN-13.
  static String computeCheckDigit(String partial) {
    int sum = 0;
    final full = partial + '0'; // temporary check digit
    for (int i = 0; i < full.length; i++) {
      final digit = int.parse(full[i]);
      final weight = (full.length - 1 - i).isOdd ? 1 : 3;
      sum += digit * weight;
    }
    final remainder = sum % 10;
    final check = remainder == 0 ? 0 : 10 - remainder;
    return check.toString();
  }
}
