import 'package:flutter/foundation.dart';

/// Ephemeral app-level state that says: "the next sale the cashier confirms
/// via POS should be appended to this already-accepted credit account, not
/// go through the handshake flow again."
///
/// Lifecycle: activated from `_FiadoDetailScreen` (Cuaderno → "Agregar a esta
/// cuenta"), consumed by `CheckoutScreen._confirmSale`, cleared immediately
/// after a successful append or when the user changes context (new customer,
/// logout, etc.). Staying active across unrelated sales would quietly mis-
/// attribute purchases — so we err on the side of clearing aggressively.
class ActiveFiadoService extends ChangeNotifier {
  String? _accountId;
  String? _customerName;
  String? _customerPhone;
  int? _balance;

  String? get accountId => _accountId;
  String? get customerName => _customerName;
  String? get customerPhone => _customerPhone;
  int? get balance => _balance;

  bool get hasActive => _accountId != null;

  void activate({
    required String accountId,
    String? customerName,
    String? customerPhone,
    int? balance,
  }) {
    _accountId = accountId;
    _customerName = customerName;
    _customerPhone = customerPhone;
    _balance = balance;
    notifyListeners();
  }

  void clear() {
    if (_accountId == null) return;
    _accountId = null;
    _customerName = null;
    _customerPhone = null;
    _balance = null;
    notifyListeners();
  }
}
