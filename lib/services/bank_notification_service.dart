import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
/// On Android the service is fed by the native
/// [`BankNotificationListener`] via a [MethodChannel] called
/// `vendia.com/notifications`. On iOS / desktop / tests the
/// channel is simply never invoked and the service stays inert
/// until [onBankNotification] is called manually.
class BankNotificationService extends ChangeNotifier {
  BankNotificationService._() {
    _bind();
  }
  static final BankNotificationService instance =
      BankNotificationService._();

  /// Native bridge identifier — must match `MainActivity.kt`.
  static const MethodChannel _channel =
      MethodChannel('vendia.com/notifications');

  bool _bound = false;

  String? _lastDetectedBank;
  DateTime? _lastDetectedAt;

  String? get lastDetectedBank => _lastDetectedBank;
  DateTime? get lastDetectedAt => _lastDetectedAt;

  void _bind() {
    if (_bound) return;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'onBankNotification') return null;
        final args = (call.arguments as Map?)?.cast<String, dynamic>();
        final label = args?['bankLabel'] as String?;
        if (label == null || label.isEmpty) return null;
        onBankNotification(bankLabel: label);
        return null;
      });
      _bound = true;
    } catch (_) {
      // setMethodCallHandler asserts that WidgetsFlutterBinding has
      // been initialized. In unit tests that don't pump a widget
      // tree (`flutter_test` without a binding init) the assertion
      // fires; we swallow it because the service is still callable
      // via the in-process [onBankNotification] path the tests use.
      // Once the app boots normally `_bind()` is re-tried.
    }
  }

  /// Called by the native bridge (or tests) every time a bank
  /// notification is captured. We intentionally do NOT persist the
  /// notification body — only the source bank label — so the
  /// Flutter logs never carry transaction data.
  void onBankNotification({required String bankLabel}) {
    // Opportunistic bind — covers the test path where the service
    // was instantiated before the binding was ready.
    _bind();
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

  /// Returns whether the user has granted the system-level
  /// "Acceso a notificaciones" toggle. Android-only — other
  /// platforms always return false. Used by an educational dialog
  /// to nudge the cashier to opt in once.
  Future<bool> isListenerEnabled() async {
    try {
      final enabled =
          await _channel.invokeMethod<bool>('isListenerEnabled');
      return enabled ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the Android system settings screen where the user can
  /// flip the listener toggle. No-op on platforms that don't
  /// implement the channel.
  Future<void> openListenerSettings() async {
    try {
      await _channel.invokeMethod('openListenerSettings');
    } on PlatformException {
      // Swallow — the cashier flow does NOT depend on this.
    } on MissingPluginException {
      // Swallow — non-Android targets.
    }
  }
}
