import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/widgets/bank_auto_detect_tile.dart';

/// Pins the "guided UX" contract:
///   * the switch reflects the OS permission state on first frame,
///   * flipping ON without the OS permission opens an [AlertDialog]
///     whose primary button is "Ir a Configuración",
///   * the dialog body carries the literal copy the PO approved,
///   * the switch never silently flips ON without the permission.
void main() {
  const channel = MethodChannel('vendia.com/notifications');

  /// Replays a fake answer from the native bridge for both
  /// `isListenerEnabled` and `openListenerSettings`. Tests can
  /// override [enabled] to simulate the post-grant state.
  void mockChannel({required bool enabled}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isListenerEnabled':
          return enabled;
        case 'openListenerSettings':
          return null;
        default:
          return null;
      }
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget host() => const MaterialApp(
        home: Scaffold(body: BankAutoDetectTile()),
      );

  testWidgets('renders the PO-approved labels', (tester) async {
    mockChannel(enabled: false);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Auto-detectar pagos de Nequi/Bancolombia'),
        findsOneWidget);
    expect(
      find.text('Lee las notificaciones del banco para agilizar el cobro'),
      findsOneWidget,
    );
  });

  testWidgets(
      'switch starts OFF when the OS listener permission is not granted',
      (tester) async {
    mockChannel(enabled: false);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isFalse);
  });

  testWidgets(
      'switch starts ON when the OS listener permission is already granted',
      (tester) async {
    mockChannel(enabled: true);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isTrue);
  });

  testWidgets(
      'tapping the switch with no permission shows the educational '
      'AlertDialog with the literal PO copy and the "Ir a '
      'Configuración" primary button', (tester) async {
    mockChannel(enabled: false);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Permiso Requerido'), findsOneWidget);
    expect(
      find.textContaining('Su privacidad está 100% garantizada'),
      findsOneWidget,
    );
    expect(find.text('Ahora no'), findsOneWidget);
    expect(find.text('Ir a Configuración'), findsOneWidget);
  });

  testWidgets('"Ahora no" closes the dialog and leaves the switch OFF',
      (tester) async {
    mockChannel(enabled: false);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();

    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.value, isFalse,
        reason:
            'CRITICAL: the switch must NOT flip ON if the cashier dismisses '
            'the dialog — the OS permission has not been granted.');
  });
}
