import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/services/tax_settings_service.dart';

/// Each test starts from a clean SharedPreferences + a fresh
/// TaxSettingsService singleton. The service swallows all prefs
/// errors silently, so we never fight platform plumbing here — we
/// just rely on the mock-storage backend SharedPreferences ships
/// for tests.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TaxSettingsService.debugResetInstance();
  });

  group('snapshotForLine', () {
    test('returns all-null when VAT is disabled', () {
      final svc = TaxSettingsService.instance;
      final snap = svc.snapshotForLine(unitPrice: 1000, quantity: 2);
      expect(snap.rate, isNull);
      expect(snap.amount, isNull);
      expect(snap.inclusive, isNull);
    });

    test('inclusive 19% on 11.900 yields exactly 1.900 extracted tax',
        () async {
      final svc = TaxSettingsService.instance;
      await svc.activate(rate: 0.19, inclusive: true);
      final snap = svc.snapshotForLine(unitPrice: 11900, quantity: 1);
      // 11900 / 1.19 = 10000 exactly → tax = 11900 - 10000 = 1900.
      expect(snap.rate, 0.19);
      expect(snap.inclusive, true);
      expect(snap.amount, isNotNull);
      expect(snap.amount!, closeTo(1900.0, 0.01));
    });

    test('exclusive 19% on 10.000 yields exactly 1.900 added tax', () async {
      final svc = TaxSettingsService.instance;
      await svc.activate(rate: 0.19, inclusive: false);
      final snap = svc.snapshotForLine(unitPrice: 10000, quantity: 1);
      expect(snap.rate, 0.19);
      expect(snap.inclusive, false);
      expect(snap.amount, closeTo(1900.0, 0.0001));
    });

    test('exclusive 19% with quantity=3 multiplies the gross', () async {
      final svc = TaxSettingsService.instance;
      await svc.activate(rate: 0.19, inclusive: false);
      final snap = svc.snapshotForLine(unitPrice: 1000, quantity: 3);
      // 1000 * 3 * 0.19 = 570
      expect(snap.amount, closeTo(570.0, 0.0001));
    });
  });

  group('persistence', () {
    test('activate + new instance loadFromPrefs recovers state', () async {
      final svc = TaxSettingsService.instance;
      await svc.activate(rate: 0.05, inclusive: false);
      expect(svc.enabled, true);
      expect(svc.rate, 0.05);
      expect(svc.inclusive, false);
      expect(svc.activatedAt, isNotNull);

      // Simulate a fresh app start.
      TaxSettingsService.debugResetInstance();
      final fresh = TaxSettingsService.instance;
      expect(fresh.enabled, false); // before load
      await fresh.loadFromPrefs();
      expect(fresh.enabled, true);
      expect(fresh.rate, 0.05);
      expect(fresh.inclusive, false);
      expect(fresh.activatedAt, isNotNull);
    });

    test('setInclusive flips flag and notifies listeners', () async {
      final svc = TaxSettingsService.instance;
      await svc.activate(rate: 0.19, inclusive: true);
      var notifyCount = 0;
      svc.addListener(() => notifyCount++);

      await svc.setInclusive(false);
      expect(svc.inclusive, false);
      expect(notifyCount, 1);

      // No-op when value already matches — avoid spurious rebuilds.
      await svc.setInclusive(false);
      expect(notifyCount, 1);
    });

    test('setRate persists and clamps to [0, 0.5]', () async {
      final svc = TaxSettingsService.instance;
      await svc.activate(rate: 0.19, inclusive: true);
      await svc.setRate(0.05);
      expect(svc.rate, 0.05);
      // Out-of-range clamps to upper bound.
      await svc.setRate(0.99);
      expect(svc.rate, 0.5);
    });

    test('deactivate keeps rate + inclusive but flips enabled off',
        () async {
      final svc = TaxSettingsService.instance;
      await svc.activate(rate: 0.19, inclusive: true);
      await svc.deactivate();
      expect(svc.enabled, false);
      expect(svc.rate, 0.19);
      expect(svc.inclusive, true);
      // Snapshot now returns all-null because enabled=false.
      final snap = svc.snapshotForLine(unitPrice: 1000, quantity: 1);
      expect(snap.rate, isNull);
      expect(snap.amount, isNull);
      expect(snap.inclusive, isNull);
    });
  });
}
