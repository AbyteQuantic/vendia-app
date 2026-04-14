import 'package:shared_preferences/shared_preferences.dart';

/// Reads and persists the global profit margin percentage.
/// Used transversally in OCR results, product creation, and admin config.
class MarginService {
  static const _key = 'vendia_default_margin';
  static const defaultMargin = 20.0;

  static Future<double> getMargin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_key) ?? defaultMargin;
  }

  static Future<void> saveMargin(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, value);
  }
}
