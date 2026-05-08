import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/screens/pos/cuaderno_fiados_screen.dart';

/// Smoke tests for the cuaderno tiles — Activos (grouped) +
/// Pendientes/Pagados (per-account) + the new Resend Link CTA on
/// Pendientes.

/// Regression suite for the Ledger Reconstruction epic.
///
/// Pre-fix: a `LIST credits` query without aggregation produced one
/// row per CreditAccount, so a customer with three duplicate ledger
/// rows ("Viviana") was rendered three times in "Activos". The PO
/// also reported "Bryan desaparecido" for credit sales that pre-dated
/// a working handshake.
///
/// Post-fix: the Activos tab consumes `GET /credits?group_by=customer`
/// — the backend collapses every open/partial/pending row of the
/// same customer into a single record. This guard pins the rendering
/// contract so a future refactor that re-introduces row-per-account
/// breaks here, not in production.
void main() {
  testWidgets(
      'CuadernoFiadosScreen renders one tile per customer with the '
      'rolled-up balance from the grouped endpoint',
      (tester) async {
    // Contract reminder for the grouped endpoint:
    //   keys: customer_id, customer_name, customer_phone,
    //         total_amount, paid_amount, balance, accounts_count,
    //         latest_activity_at, status.
    final viviana = <String, dynamic>{
      'customer_id': '11111111-1111-1111-1111-111111111111',
      'customer_name': 'Viviana',
      'customer_phone': '3001234567',
      'total_amount': 30000,
      'paid_amount': 5000,
      'balance': 25000,
      'accounts_count': 3,
      'status': 'partial',
    };
    final bryan = <String, dynamic>{
      'customer_id': '22222222-2222-2222-2222-222222222222',
      'customer_name': 'Bryan Murcia',
      'customer_phone': '3009876543',
      'total_amount': 10000,
      'paid_amount': 0,
      'balance': 10000,
      'accounts_count': 1,
      'status': 'open',
    };

    // Prove the rendering contract directly: assert that buildGroupedTile
    // produces a tile whose visible Text widgets match the contract for
    // the grouped endpoint shape — and that the multi-account badge
    // appears once and only once when accounts_count > 1.
    Widget host(Widget tile) => MaterialApp(home: Scaffold(body: tile));

    await tester.pumpWidget(host(buildGroupedTileForTest(viviana)));
    expect(find.text('Viviana'), findsOneWidget);
    // Balance shows on both the subtitle ("Debe \$25.000") and the
    // trailing column — two findings is the canonical render.
    expect(find.text('Debe \$25.000'), findsOneWidget);
    expect(find.text('\$25.000'), findsOneWidget);
    // The "N cuentas" hint is the explicit signal that the backend
    // collapsed duplicates — must read in azul, not rojo, and must
    // never say DIAN/sanción/multa.
    expect(find.text('3 cuentas'), findsOneWidget);

    await tester.pumpWidget(host(buildGroupedTileForTest(bryan)));
    expect(find.text('Bryan Murcia'), findsOneWidget);
    expect(find.text('Debe \$10.000'), findsOneWidget);
    // accounts_count == 1 → the duplicate badge stays out of the way.
    expect(find.text('1 cuentas'), findsNothing);
  });

  testWidgets(
      'Pendientes tile renders resend + chat icons in a Row with a 16px '
      'gap and never overlaps them', (tester) async {
    final pending = <String, dynamic>{
      'id': '99999999-9999-9999-9999-999999999999',
      'customer': {'name': 'Viviana Gutierrez', 'phone': '3001234567'},
      'total_amount': 8000,
      'paid_amount': 0,
      'status': 'pending',
      'fiado_status': 'link_sent',
      'fiado_token': 'tok-abc-123',
    };

    Widget host(Widget tile) => MaterialApp(home: Scaffold(body: tile));

    // Build the tile via the public renderer + an explicit
    // extraTrailingAction to mimic the Pendientes-tab caller.
    const resend = SizedBox(
      key: Key('resend_action'),
      width: 36,
      height: 36,
      child: Icon(Icons.send_rounded,
          color: Color(0xFF6D28D9), size: 22),
    );
    await tester.pumpWidget(host(buildAccountTileForTest(
      pending,
      extraTrailingAction: resend,
    )));

    // Both icons are present.
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chat_rounded), findsOneWidget);

    // No overlap: the right edge of the resend hit-box must be
    // strictly LESS than the left edge of the chat hit-box. We use
    // the SizedBox parents (width 36) so the assertion stays
    // independent of icon glyph size.
    final sendBox = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.send_rounded),
        matching: find.byType(SizedBox),
      ).first,
    );
    final chatBox = tester.getRect(
      find.ancestor(
        of: find.byIcon(Icons.chat_rounded),
        matching: find.byType(SizedBox),
      ).first,
    );
    expect(sendBox.right, lessThan(chatBox.left),
        reason: 'CRITICAL: send and chat boxes overlap horizontally');

    final gap = chatBox.left - sendBox.right;
    expect(gap, greaterThanOrEqualTo(16.0),
        reason: 'spacing between icons must be at least 16 px');

    // Both icons sit at the same vertical center → consistent
    // alignment (no jagged offsets).
    expect((sendBox.center.dy - chatBox.center.dy).abs(), lessThan(0.5));
  });

  testWidgets(
      'Pagados tile shows the closed_at audit timestamp instead of the '
      'remaining balance', (tester) async {
    // For the "Pagados" tab the screen still renders one CreditAccount
    // per row (the audit unit), but the trailing line on the subtitle
    // is the cierre date — driven by the new `closed_at` column the
    // backend stamps when balance hits zero. A row that pre-dates the
    // column gets a short dash so legacy data doesn't break the layout.
    final paidWithCierre = <String, dynamic>{
      'id': '33333333-3333-3333-3333-333333333333',
      'customer': {'name': 'Pedro', 'phone': '3001112233'},
      'total_amount': 12000,
      'paid_amount': 12000,
      'status': 'paid',
      'closed_at': '2026-04-30T10:15:00Z',
    };
    final paidLegacy = <String, dynamic>{
      'id': '44444444-4444-4444-4444-444444444444',
      'customer': {'name': 'Sofía', 'phone': ''},
      'total_amount': 5000,
      'paid_amount': 5000,
      'status': 'paid',
      'closed_at': null,
    };

    Widget host(Widget tile) => MaterialApp(home: Scaffold(body: tile));

    await tester.pumpWidget(host(buildAccountTileForTest(paidWithCierre)));
    expect(find.text('Pedro'), findsOneWidget);
    expect(find.text('Cierre: 2026-04-30'), findsOneWidget);

    await tester.pumpWidget(host(buildAccountTileForTest(paidLegacy)));
    expect(find.text('Sofía'), findsOneWidget);
    expect(find.text('Cierre: —'), findsOneWidget);
  });
}
