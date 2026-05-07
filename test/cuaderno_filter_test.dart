import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/pos/cuaderno_fiados_screen.dart';

/// Regression suite for the P0 "fiado fantasma" report
/// (hotfix/p0-cuaderno-orphan-fiados).
///
/// Backend state machine for credit_accounts.status:
///   pending → open → partial → paid   (or cancelled at any point)
///
/// Pre-fix: Cuaderno's "Activos" tab sent ?status=open and the
/// backend filter was strict equality. Once a customer made one
/// abono, status flipped to 'partial' and the row vanished from
/// the cashier's list, even though the debt was still active.
///
/// Post-fix: "Activos" partitions client-side and includes both
/// `open` and `partial`. The exact PO repro ("Bryan Murcia") must
/// stay visible after registering an abono.
void main() {
  group('filterCreditsForTab — base partition rules', () {
    final fixtures = <Map<String, dynamic>>[
      {
        'id': 'c-1',
        'status': 'open',
        'customer': {'name': 'Cliente Activo Sin Abonos'},
        'total_amount': 50000,
        'paid_amount': 0,
      },
      {
        'id': 'c-2',
        'status': 'partial',
        'customer': {'name': 'Cliente Con Abono Parcial'},
        'total_amount': 80000,
        'paid_amount': 30000,
      },
      {
        'id': 'c-3',
        'status': 'pending',
        'customer': {'name': 'Cliente Aún No Acepta'},
        'total_amount': 25000,
        'paid_amount': 0,
      },
      {
        'id': 'c-4',
        'status': 'paid',
        'customer': {'name': 'Cliente Saldado'},
        'total_amount': 40000,
        'paid_amount': 40000,
      },
      {
        'id': 'c-5',
        'status': 'cancelled',
        'customer': {'name': 'Cliente Anulado'},
        'total_amount': 10000,
        'paid_amount': 0,
      },
    ];

    test('"active" tab includes both open and partial — never paid/pending/cancelled', () {
      final result = filterCreditsForTab(fixtures, 'active');
      final ids = result.map((c) => c['id'] as String).toList();
      expect(ids, containsAll(<String>['c-1', 'c-2']));
      expect(ids, isNot(contains('c-3')));
      expect(ids, isNot(contains('c-4')));
      expect(ids, isNot(contains('c-5')));
      expect(result.length, 2);
    });

    test('"pending" tab returns only status=pending (link sent / opened)', () {
      final result = filterCreditsForTab(fixtures, 'pending');
      expect(result.length, 1);
      expect(result.first['id'], 'c-3');
    });

    test('"paid" tab returns only status=paid', () {
      final result = filterCreditsForTab(fixtures, 'paid');
      expect(result.length, 1);
      expect(result.first['id'], 'c-4');
    });

    test('cancelled rows are dropped from every tab', () {
      for (final tab in const ['active', 'pending', 'paid']) {
        final result = filterCreditsForTab(fixtures, tab);
        expect(
          result.where((c) => c['id'] == 'c-5'),
          isEmpty,
          reason: 'cancelled fiado leaked into "$tab" tab',
        );
      }
    });

    test('unknown tab name returns empty list (defensive default)', () {
      expect(filterCreditsForTab(fixtures, 'partial'), isEmpty);
      expect(filterCreditsForTab(fixtures, 'all'), isEmpty);
      expect(filterCreditsForTab(fixtures, ''), isEmpty);
    });

    test('missing status field defaults to open (legacy fixture safety)', () {
      // Some early-2026 production rows were inserted before the
      // status column had a default — `null` should still surface
      // in "Activos" so the cashier can reconcile manually instead
      // of the row vanishing.
      final legacy = <Map<String, dynamic>>[
        {
          'id': 'legacy-1',
          'customer': {'name': 'Pre-migration row'},
          'total_amount': 15000,
          'paid_amount': 5000,
        },
      ];
      final result = filterCreditsForTab(legacy, 'active');
      expect(result.length, 1);
      expect(result.first['id'], 'legacy-1');
    });
  });

  group('Bryan Murcia repro — exact PO report', () {
    // Customer with a fiado accepted server-side. After the cashier
    // registers a partial abono, the row's status flips from 'open'
    // to 'partial' and the original "?status=open" query stopped
    // returning it. With the fix, "Activos" still surfaces it.
    final bryanFiado = <String, dynamic>{
      'id': 'bryan-credit-001',
      'status': 'partial',
      'fiado_status': 'accepted',
      'total_amount': 120000,
      'paid_amount': 50000,
      'customer': {
        'name': 'Bryan Murcia',
        'phone': '3001112233',
      },
    };

    test('Bryan stays visible in Activos after first abono', () {
      final all = <Map<String, dynamic>>[bryanFiado];
      final activos = filterCreditsForTab(all, 'active');
      expect(activos.length, 1);
      expect(activos.first['customer']['name'], 'Bryan Murcia');
      expect(activos.first['paid_amount'], 50000);
      expect(activos.first['total_amount'], 50000 + 70000);
    });

    test('Bryan does NOT appear in "pending" (he already accepted)', () {
      final all = <Map<String, dynamic>>[bryanFiado];
      expect(filterCreditsForTab(all, 'pending'), isEmpty);
    });

    test('Bryan does NOT appear in "paid" (still owes 70000)', () {
      final all = <Map<String, dynamic>>[bryanFiado];
      expect(filterCreditsForTab(all, 'paid'), isEmpty);
    });

    test('After Bryan settles the remaining 70000, status=paid moves him out of Activos', () {
      final settled = Map<String, dynamic>.from(bryanFiado)
        ..['status'] = 'paid'
        ..['paid_amount'] = 120000;
      final all = <Map<String, dynamic>>[settled];

      expect(filterCreditsForTab(all, 'active'), isEmpty);
      expect(filterCreditsForTab(all, 'paid').length, 1);
    });
  });

  group('Total por cobrar invariants', () {
    // The header sum should reflect everything the cashier still
    // expects to receive — i.e. (total - paid) across every
    // non-paid/non-cancelled row currently visible. Pre-fix the
    // sum silently dropped partials.
    int sumOutstanding(List<Map<String, dynamic>> rows) {
      return rows.fold<int>(0, (acc, c) {
        final total = (c['total_amount'] as num?)?.toInt() ?? 0;
        final paid = (c['paid_amount'] as num?)?.toInt() ?? 0;
        return acc + (total - paid);
      });
    }

    test('sum across Activos counts open + partial balances', () {
      final raw = <Map<String, dynamic>>[
        {'id': 'a', 'status': 'open', 'total_amount': 30000, 'paid_amount': 0},
        {
          'id': 'b',
          'status': 'partial',
          'total_amount': 100000,
          'paid_amount': 40000,
        },
        {'id': 'c', 'status': 'pending', 'total_amount': 9999, 'paid_amount': 0},
        {'id': 'd', 'status': 'paid', 'total_amount': 12345, 'paid_amount': 12345},
      ];
      final activos = filterCreditsForTab(raw, 'active');
      // 30000 (open balance) + 60000 (partial remaining) = 90000
      expect(sumOutstanding(activos), 90000);
    });
  });
}
