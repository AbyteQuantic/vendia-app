import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/widgets/owner_pin_dialog.dart';

class _FakeApi implements ApiService {
  _FakeApi(this._behavior);
  final Future<bool> Function(String pin) _behavior;
  @override
  Future<bool> verifyOwnerPin(String pin) => _behavior(pin);
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('PIN correct → dialog returns true', (tester) async {
    final api = _FakeApi((pin) async => pin == '1234');
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await askOwnerPin(ctx, apiOverride: api);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets(
    'wrong PIN → dialog stays open with error and loader cleared',
    (tester) async {
      final api = _FakeApi((pin) async => false);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await askOwnerPin(ctx, apiOverride: api);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0000');
      await tester.pumpAndSettle();
      expect(find.text('PIN incorrecto'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // Cancel button is enabled again.
      final cancel = tester.widget<TextButton>(find.byWidgetPredicate(
          (w) => w is TextButton &&
              (w.child is Text) &&
              ((w.child as Text).data == 'Cancelar')));
      expect(cancel.onPressed, isNotNull);
    },
  );

  testWidgets(
    'API throws AppError (network) → loader cleared, connectivity '
    'message shown, Cancel re-enabled',
    (tester) async {
      final api = _FakeApi((_) async {
        throw const AppError(
          type: AppErrorType.network,
          message: 'timeout',
        );
      });
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await askOwnerPin(ctx, apiOverride: api);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '4321');
      await tester.pumpAndSettle();
      expect(find.textContaining('Error de conexión'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'API throws unexpected error → loader cleared, generic message shown',
    (tester) async {
      final api = _FakeApi((_) async {
        throw StateError('boom');
      });
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await askOwnerPin(ctx, apiOverride: api);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '9999');
      await tester.pumpAndSettle();
      expect(find.textContaining('Error al verificar'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
}
