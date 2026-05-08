import 'package:flutter/foundation.dart';

/// Purely informative listener for native bank-app notifications
/// (Bancolombia, Nequi, Daviplata, etc.). Per the PO mandate this
/// service NEVER:
///   * enables a "Confirm payment" button,
///   * auto-closes a dialog or modal,
///   * mutates any form state.
///
/// The only contract is: when a bank notif lands the UI flashes a
/// green SnackBar so the cashier knows the customer's transfer
/// arrived. The actual confirmation MUST come from a photo of the
/// receipt (see [ReceiptImagePicker]).
///
/// The Android wiring (`NotificationListenerService` →
/// `MethodChannel('vendia/bank_notifications')`) is documented as
/// TODO — the Dart-side service is intentionally complete and
/// callable by tests / future native bridge alike.
class BankNotificationService extends ChangeNotifier {
  BankNotificationService._();
  static final BankNotificationService instance =
      BankNotificationService._();

  /// Last detected bank label (e.g. `Bancolombia`). UI reads this
  /// to render the SnackBar text. Never used as input to a
  /// validation or button-enable rule.
  String? _lastDetectedBank;
  DateTime? _lastDetectedAt;

  String? get lastDetectedBank => _lastDetectedBank;
  DateTime? get lastDetectedAt => _lastDetectedAt;

  /// Called by the native bridge (or tests) every time a bank
  /// notification is captured. We intentionally do NOT read the
  /// notification body — only the source bank label — so we never
  /// risk leaking transaction data into an unencrypted local log.
  void onBankNotification({required String bankLabel}) {
    _lastDetectedBank = bankLabel;
    _lastDetectedAt = DateTime.now();
    notifyListeners();
  }

  /// Called when a payment flow finishes (or is cancelled) so the
  /// next sale starts with a clean slate.
  void reset() {
    _lastDetectedBank = null;
    _lastDetectedAt = null;
    notifyListeners();
  }
}
