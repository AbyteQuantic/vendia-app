import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/dashboard/payment_methods_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';

/// Tiny fake ApiService that lets each test control what the list
/// call does — succeeds, fails, or hangs forever. Nothing else the
/// screen touches during the initial load is covered here, so
/// overriding only `fetchPaymentMethods` keeps the fake minimal.
class _FakeApi extends ApiService {
  _FakeApi({this.onList}) : super(AuthService());

  final Future<List<Map<String, dynamic>>> Function()? onList;

  @override
  Future<List<Map<String, dynamic>>> fetchPaymentMethods() {
    if (onList == null) return Future.value(const []);
    return onList!();
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('PaymentMethodsScreen (P0: no infinite loader)', () {
    testWidgets('empty success → renders empty state + add button, no spinner',
        (tester) async {
      final api = _FakeApi(onList: () async => const []);
      await tester.pumpWidget(
          _wrap(PaymentMethodsScreen(apiOverride: api)));
      // Let microtasks and one frame pass — fetch resolves with [].
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pm_empty_state')), findsOneWidget);
      expect(find.byKey(const Key('pm_add_method_button')), findsOneWidget);
      // Top banners are both absent on success.
      expect(find.byKey(const Key('pm_loading_banner')), findsNothing);
      expect(find.byKey(const Key('pm_error_banner')), findsNothing);
    });

    testWidgets('AppError → error banner with Reintentar, empty state visible',
        (tester) async {
      final api = _FakeApi(
        onList: () async => throw const AppError(
            type: AppErrorType.network, message: 'Sin conexión'),
      );
      await tester.pumpWidget(
          _wrap(PaymentMethodsScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pm_error_banner')), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      // Critical invariant: the user can STILL add a method.
      expect(find.byKey(const Key('pm_empty_state')), findsOneWidget);
      expect(find.byKey(const Key('pm_add_method_button')), findsOneWidget);
    });

    testWidgets('unexpected exception is caught, empty state still rendered',
        (tester) async {
      // A TypeError from _extractList falling through the try/catch
      // was the smoking gun for the regression. Simulate by raising
      // a non-AppError synchronously from the fake.
      final api = _FakeApi(
        onList: () => Future<List<Map<String, dynamic>>>.error(
            TypeError(), StackTrace.current),
      );
      await tester.pumpWidget(
          _wrap(PaymentMethodsScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pm_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('pm_empty_state')), findsOneWidget);
      expect(find.byKey(const Key('pm_add_method_button')), findsOneWidget);
    });

    testWidgets(
        'hanging request → 8s timeout clears loading and shows empty state',
        (tester) async {
      // Never-completing future, reproducing the captive-wifi
      // / stuck-refresh-token scenario from production. The
      // screen's internal timeout must bail us out.
      final api = _FakeApi(
        onList: () => Completer<List<Map<String, dynamic>>>().future,
      );
      await tester.pumpWidget(
          _wrap(PaymentMethodsScreen(apiOverride: api)));

      // Initially the first-load banner is visible.
      await tester.pump();
      expect(find.byKey(const Key('pm_loading_banner')), findsOneWidget);
      // ...but crucially, the empty state + add button are ALSO
      // already on screen. The screen is interactive even while
      // the request is in flight.
      expect(find.byKey(const Key('pm_empty_state')), findsOneWidget);
      expect(find.byKey(const Key('pm_add_method_button')), findsOneWidget);

      // Advance past the 8 s internal timeout.
      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      // Loading banner gone, error banner in, form still reachable.
      expect(find.byKey(const Key('pm_loading_banner')), findsNothing);
      expect(find.byKey(const Key('pm_error_banner')), findsOneWidget);
      expect(find.byKey(const Key('pm_empty_state')), findsOneWidget);
      expect(find.byKey(const Key('pm_add_method_button')), findsOneWidget);
    });

    testWidgets('populated success → renders method cards, no banners',
        (tester) async {
      final api = _FakeApi(onList: () async => [
            {
              'id': 'm1',
              'name': 'Nequi',
              'provider': 'nequi',
              'account_details': '300 123 4567',
              'is_active': true,
            },
          ]);
      await tester.pumpWidget(
          _wrap(PaymentMethodsScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      expect(find.text('Nequi'), findsOneWidget);
      expect(find.text('300 123 4567'), findsOneWidget);
      expect(find.byKey(const Key('pm_loading_banner')), findsNothing);
      expect(find.byKey(const Key('pm_error_banner')), findsNothing);
    });

    testWidgets('tapping Agregar Método opens the create bottom sheet',
        (tester) async {
      final api = _FakeApi(onList: () async => const []);
      await tester.pumpWidget(
          _wrap(PaymentMethodsScreen(apiOverride: api)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pm_add_method_button')));
      await tester.pumpAndSettle();

      expect(find.text('Nuevo Método de Pago'), findsOneWidget);
      expect(find.text('¿Por dónde le pagan?'), findsOneWidget);
      // The dropdown landed on the first preset (Nequi).
      expect(find.text('Nequi'), findsOneWidget);
    });
  });
}
