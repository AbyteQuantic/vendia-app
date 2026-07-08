// Spec: specs/100-completar-skus-inventario/spec.md (T-16, T-18)
//
// SkuCompletionScreen: lista solo los productos recibidos; cada tarjeta
// muestra foto/nombre/precio y 3 acciones (Escanear/Generar/Digitar); al
// asignar con éxito la tarjeta sale y el contador baja; al vaciar aparece
// el estado de éxito. Duplicados: pre-check o 409 → tarjeta de conflicto
// con el producto dueño (Omitir/Corregir), NUNCA asigna en silencio;
// código GENERADO que colisiona → regenera y reintenta solo (máx 3).
// Error de red → banner honesto + Reintentar, la tarjeta no se marca hecha.

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/sku_completion_screen.dart';
import 'package:vendia_pos/screens/inventory/sku_scan_session_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  /// Dueño devuelto por el pre-check para un código exacto.
  final Map<String, Map<String, dynamic>> ownersByCode = {};

  /// Si > 0, las primeras N consultas devuelven este dueño sin importar el
  /// código (simula colisiones seguidas de un código GENERADO al azar).
  int conflictFirstN = 0;
  Map<String, dynamic>? conflictOwner;

  /// Error a lanzar en updateProduct (null = éxito).
  Object? updateError;

  int lookupCalls = 0;
  final List<MapEntry<String, Map<String, dynamic>>> patched = [];

  @override
  Future<Map<String, dynamic>?> lookupProductByBarcode(String code) async {
    lookupCalls++;
    if (conflictFirstN > 0 && lookupCalls <= conflictFirstN) {
      return conflictOwner;
    }
    return ownersByCode[code];
  }

  @override
  Future<Map<String, dynamic>> updateProduct(
      String id, Map<String, dynamic> data) async {
    final err = updateError;
    if (err != null) throw err;
    patched.add(MapEntry(id, data));
    return {'id': id, ...data};
  }
}

Map<String, dynamic> _p(String id, String name, {num price = 2500}) => {
      'id': id,
      'name': name,
      'barcode': '',
      'price': price,
      'presentation': 'Unidad',
      'photo_url': '',
      'image_url': '',
    };

Future<void> _digitar(WidgetTester tester, String code,
    {int cardIndex = 0}) async {
  await tester.tap(find.text('Digitar').at(cardIndex));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, code);
  await tester.tap(find.text('Guardar'));
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  Widget wrap(Widget child) => MaterialApp(home: child);

  group('T-16 — lista, tarjetas y estado de éxito', () {
    testWidgets('lista solo los productos recibidos con precio y 3 acciones',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana'), _p('2', 'Panela', price: 4200)],
      )));
      await tester.pump();

      expect(find.text('Arroz Diana'), findsOneWidget);
      expect(find.text('Panela'), findsOneWidget);
      expect(find.text('\$2.500'), findsOneWidget);
      expect(find.text('\$4.200'), findsOneWidget);
      expect(find.text('0 de 2 completados'), findsOneWidget);
      expect(find.text('Escanear'), findsNWidgets(2));
      expect(find.text('Generar'), findsNWidgets(2));
      expect(find.text('Digitar'), findsNWidgets(2));
    });

    testWidgets('digitar un código válido asigna, saca la tarjeta y baja el '
        'contador (AC-02)', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana'), _p('2', 'Panela')],
      )));
      await tester.pump();

      await _digitar(tester, '7702004003508');

      expect(api.patched.length, 1);
      expect(api.patched.first.key, '1');
      expect(api.patched.first.value['barcode'], '7702004003508');
      expect(find.text('Arroz Diana'), findsNothing); // la tarjeta salió
      expect(find.text('1 de 2 completados'), findsOneWidget);
    });

    testWidgets('al vaciar la lista aparece el estado de éxito (AC-05)',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana')],
      )));
      await tester.pump();

      await _digitar(tester, '7702004003508');

      expect(find.text('¡Todo completo!'), findsOneWidget);
    });

    testWidgets('lista vacía de entrada → estado de éxito, sin tarjetas',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(
          wrap(SkuCompletionScreen(apiOverride: api, products: const [])));
      await tester.pump();

      expect(find.text('¡Todo completo!'), findsOneWidget);
      expect(find.text('Digitar'), findsNothing);
    });

    testWidgets('código digitado inválido no se guarda (validación)',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana')],
      )));
      await tester.pump();

      await _digitar(tester, 'ab'); // muy corto

      expect(api.patched, isEmpty);
      expect(find.text('Arroz Diana'), findsOneWidget); // sigue pendiente
    });
  });

  group('T-18 — duplicados y errores', () {
    testWidgets('pre-check: código de OTRO producto → tarjeta de conflicto '
        'con el dueño, sin asignar (AC-04)', (tester) async {
      final api = _FakeApi()
        ..ownersByCode['7591'] = {
          'id': 'otro',
          'name': 'Coca-Cola 350ml',
          'presentation': 'Botella',
        };
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana')],
      )));
      await tester.pump();

      await _digitar(tester, '7591');

      expect(api.patched, isEmpty); // NUNCA asigna en silencio
      expect(find.textContaining('Coca-Cola 350ml'), findsOneWidget);
      expect(find.text('Omitir'), findsOneWidget);
      expect(find.text('Corregir'), findsOneWidget);
      expect(find.text('0 de 1 completados'), findsOneWidget);

      // Omitir descarta el código y la tarjeta sigue pendiente.
      await tester.tap(find.text('Omitir'));
      await tester.pumpAndSettle();
      expect(find.text('Omitir'), findsNothing);
      expect(find.text('Arroz Diana'), findsOneWidget);
    });

    testWidgets('409 del backend → misma tarjeta de conflicto', (tester) async {
      final api = _FakeApi()
        ..updateError = const AppError(
          type: AppErrorType.validation,
          message: 'Ese código ya pertenece a otro producto.',
          statusCode: 409,
          errorCode: 'duplicate_barcode',
          payload: {
            'error': 'duplicate_barcode',
            'existing_product': {
              'id': 'otro',
              'name': 'Panela San José',
              'presentation': 'Paquete',
            },
          },
        );
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana')],
      )));
      await tester.pump();

      await _digitar(tester, '7702004003508');

      expect(find.textContaining('Panela San José'), findsOneWidget);
      expect(find.text('Omitir'), findsOneWidget);
      expect(find.text('Corregir'), findsOneWidget);
      expect(find.text('0 de 1 completados'), findsOneWidget);
    });

    testWidgets('código GENERADO que colisiona se regenera solo (máx 3) y '
        'asigna sin molestar al tendero', (tester) async {
      final api = _FakeApi()
        ..conflictFirstN = 2
        ..conflictOwner = {'id': 'otro', 'name': 'Otro producto'};
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Empanada')],
      )));
      await tester.pump();

      await tester.tap(find.text('Generar'));
      await tester.pumpAndSettle();
      // El tendero ve el código propuesto (FR-05/FR-13).
      expect(find.textContaining('VND-UNI-EMP-'), findsOneWidget);

      await tester.tap(find.text('Guardar'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // 2 colisiones silenciosas + 1 lookup limpio → guardado.
      expect(api.lookupCalls, 3);
      expect(api.patched.length, 1);
      expect(api.patched.first.value['barcode'], startsWith('VND-UNI-EMP-'));
      expect(find.text('Omitir'), findsNothing); // sin conflicto visible
      expect(find.text('¡Todo completo!'), findsOneWidget);
    });

    testWidgets('"Generar otro" propone un código nuevo antes de guardar '
        '(FR-13)', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Empanada')],
      )));
      await tester.pump();

      await tester.tap(find.text('Generar'));
      await tester.pumpAndSettle();
      expect(find.text('Generar otro'), findsOneWidget);
      await tester.tap(find.text('Generar otro'));
      await tester.pump();
      expect(find.textContaining('VND-UNI-EMP-'), findsOneWidget);
      expect(api.patched, isEmpty); // nada guardado todavía
    });

    testWidgets('error de red → banner honesto + Reintentar; la tarjeta NO '
        'se marca hecha', (tester) async {
      final api = _FakeApi()
        ..updateError = const AppError(
          type: AppErrorType.network,
          message: 'No pudimos conectar.',
        );
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana')],
      )));
      await tester.pump();

      await _digitar(tester, '7702004003508');

      expect(api.patched, isEmpty);
      expect(find.textContaining('Sin conexión'), findsOneWidget);
      expect(find.textContaining('Arroz Diana'), findsWidgets);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('0 de 1 completados'), findsOneWidget);

      // Vuelve la señal → Reintentar guarda y la tarjeta sale.
      api.updateError = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.length, 1);
      expect(find.text('¡Todo completo!'), findsOneWidget);
    });
  });

  group('T-22 — modo ráfaga', () {
    testWidgets('con >1 pendiente el botón aparece y abre la sesión; al '
        'asignar allá, la lista de acá se sincroniza', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        scanSessionKeyboardOnly: true,
        products: [_p('1', 'Arroz Diana'), _p('2', 'Panela')],
      )));
      await tester.pump();

      expect(find.text('Modo ráfaga'), findsOneWidget);
      await tester.tap(find.text('Modo ráfaga'));
      await tester.pumpAndSettle();
      expect(find.byType(SkuScanSessionScreen), findsOneWidget);

      // Asigna un código en la sesión y vuelve.
      await tester.enterText(find.byType(TextField).first, '1111');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(SkuScanSessionScreen))).pop();
      await tester.pumpAndSettle();

      expect(api.patched.length, 1);
      expect(find.text('1 de 2 completados'), findsOneWidget);
      expect(find.text('Arroz Diana'), findsNothing); // sincronizada
    });

    testWidgets('con 1 solo pendiente el botón no aparece', (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(wrap(SkuCompletionScreen(
        apiOverride: api,
        products: [_p('1', 'Arroz Diana')],
      )));
      await tester.pump();

      expect(find.text('Modo ráfaga'), findsNothing);
    });
  });
}
