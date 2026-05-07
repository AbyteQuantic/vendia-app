import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only persistence layer for VAT (IVA) settings. Lives in
/// SharedPreferences for now — a future backend PR will sync these
/// fields onto the Tenant row and reconcile on login. The service
/// MUST stay completely self-contained so a future swap to a remote
/// source only changes the load/persist plumbing, not the call sites.
///
/// Two policies bake into the math:
///   • [enabled] — global on/off. While off, [snapshotForLine] always
///     returns null bytes, which the sale flow writes verbatim into
///     SaleItemEmbed. Pre-activation sales therefore stay legacy
///     (taxRate=null, taxAmount=null, isTaxInclusive=null) forever.
///   • [inclusive] — true: the displayed price already contains the
///     VAT. The customer pays unitPrice*qty exactly; the tax amount
///     is extracted from inside that figure. false: VAT is added on
///     top, the customer pays unitPrice*qty + tax.
///
/// The PO mandate is "default Inclusive" — Colombia retail convention —
/// but the owner can flip it from the Settings screen at any time.
class TaxSettingsService extends ChangeNotifier {
  TaxSettingsService._();

  // Singleton with a test override seam mirroring HardwareService so
  // unit tests can run with a clean state without leaking prefs into
  // siblings.
  static TaxSettingsService _instance = TaxSettingsService._();
  static TaxSettingsService get instance => _instance;

  @visibleForTesting
  static void debugOverrideInstance(TaxSettingsService override) {
    _instance = override;
  }

  @visibleForTesting
  static void debugResetInstance() {
    _instance = TaxSettingsService._();
  }

  // SharedPreferences keys — kept private + namespaced so we can grep
  // when the backend sync PR lands and we map them onto tenant columns.
  static const String _kEnabled = 'tax_vat_enabled';
  static const String _kRate = 'tax_vat_rate';
  static const String _kInclusive = 'tax_vat_inclusive_pricing';
  static const String _kActivatedAt = 'tax_vat_activated_at';

  bool _enabled = false;
  double _rate = 0.19; // Colombia general default
  bool _inclusive = true; // PO mandate: default Inclusive
  DateTime? _activatedAt;

  bool get enabled => _enabled;
  double get rate => _rate;
  bool get inclusive => _inclusive;
  DateTime? get activatedAt => _activatedAt;

  /// Hydrate from SharedPreferences. Idempotent. Never throws — a
  /// prefs failure leaves us with the safe default of "VAT disabled".
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      final storedRate = prefs.getDouble(_kRate);
      if (storedRate != null) _rate = storedRate;
      final storedInclusive = prefs.getBool(_kInclusive);
      if (storedInclusive != null) _inclusive = storedInclusive;
      final storedActivatedAtMs = prefs.getInt(_kActivatedAt);
      if (storedActivatedAtMs != null) {
        _activatedAt =
            DateTime.fromMillisecondsSinceEpoch(storedActivatedAtMs);
      }
    } catch (_) {
      // Prefs not available — keep defaults, don't crash the app.
    } finally {
      notifyListeners();
    }
  }

  /// First-time activation through the wizard. Atomic by design — all
  /// 4 keys land before the listener fan-out runs, so a settings UI
  /// rebuild never sees a half-applied state.
  Future<void> activate({
    required double rate,
    required bool inclusive,
  }) async {
    _enabled = true;
    _rate = rate;
    _inclusive = inclusive;
    _activatedAt = DateTime.now();
    await _persistAll();
    notifyListeners();
  }

  /// Live toggle from the Settings screen. Does NOT touch [enabled]
  /// or [activatedAt] — those are bound to the wizard.
  Future<void> setInclusive(bool value) async {
    if (_inclusive == value) return;
    _inclusive = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kInclusive, value);
    } catch (_) {
      // Persist failure is non-fatal — in-memory state is still useful
      // for the rest of the session and will retry on next mutation.
    }
    notifyListeners();
  }

  /// Live tax-rate update from Settings. Constrained to [0, 0.5] to
  /// match the wizard input bounds.
  Future<void> setRate(double rate) async {
    final clamped = rate.clamp(0.0, 0.5).toDouble();
    if (_rate == clamped) return;
    _rate = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kRate, clamped);
    } catch (_) {
      // Same rationale as setInclusive — keep memory state, ignore.
    }
    notifyListeners();
  }

  /// Soft turn-off. Keeps [rate] + [inclusive] so re-activation
  /// doesn't ask the owner to choose them again. Past sales' VAT
  /// snapshots are untouched — the historical math freezes at sale
  /// time, not at the moment we toggle.
  Future<void> deactivate() async {
    if (!_enabled) return;
    _enabled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, false);
    } catch (_) {
      // Non-fatal.
    }
    notifyListeners();
  }

  /// Compute the tax bytes for a single line at the current settings.
  /// Returns the (rate, amount, inclusive) snapshot ready to freeze
  /// onto a SaleItemEmbed. When VAT is off the tuple is all-null —
  /// the call site assigns directly so legacy "no VAT" rows stay
  /// indistinguishable from pre-feature data.
  ({double? rate, double? amount, bool? inclusive}) snapshotForLine({
    required double unitPrice,
    required int quantity,
  }) {
    if (!_enabled) {
      return (rate: null, amount: null, inclusive: null);
    }
    final lineGross = unitPrice * quantity;
    double tax;
    if (_inclusive) {
      // Customer paid unitPrice already including VAT. Extract.
      // Example: 11.900 inclusive @ 19% → 11900 - 11900/1.19 = 1900.
      tax = lineGross - (lineGross / (1 + _rate));
    } else {
      // VAT added on top.
      tax = lineGross * _rate;
    }
    return (rate: _rate, amount: tax, inclusive: _inclusive);
  }

  Future<void> _persistAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, _enabled);
      await prefs.setDouble(_kRate, _rate);
      await prefs.setBool(_kInclusive, _inclusive);
      if (_activatedAt != null) {
        await prefs.setInt(
          _kActivatedAt,
          _activatedAt!.millisecondsSinceEpoch,
        );
      }
    } catch (_) {
      // Non-fatal — the in-memory state is still authoritative for
      // the rest of the session.
    }
  }
}
