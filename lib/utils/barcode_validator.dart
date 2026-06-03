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

  /// EAN/UPC checksum (GTIN modulo-10). Pesa cada dígito según su
  /// distancia desde la derecha: el dígito de control (el más a la
  /// derecha, distancia 0) pesa 1, el siguiente pesa 3, y así alternando
  /// 1,3,1,3… El código es válido si la suma ponderada es múltiplo de 10.
  /// Esta regla unifica EAN-8, UPC-A(12), EAN-13 e ITF-14.
  static bool _checkEan(String code) {
    int sum = 0;
    for (int i = 0; i < code.length; i++) {
      final digit = int.parse(code[i]);
      // Distancia desde la derecha: par → peso 1, impar → peso 3.
      // (Antes estaba invertido — rechazaba códigos EAN-13 válidos como
      // 7702005004467.)
      final weight = (code.length - 1 - i).isEven ? 1 : 3;
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
    final full = '${partial}0'; // dígito de control temporal (aporta 0)
    for (int i = 0; i < full.length; i++) {
      final digit = int.parse(full[i]);
      // Misma regla que _checkEan: distancia par desde la derecha → peso 1.
      final weight = (full.length - 1 - i).isEven ? 1 : 3;
      sum += digit * weight;
    }
    final remainder = sum % 10;
    final check = remainder == 0 ? 0 : 10 - remainder;
    return check.toString();
  }
}
