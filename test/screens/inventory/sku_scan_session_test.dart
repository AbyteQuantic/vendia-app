// Spec: specs/100-completar-skus-inventario/spec.md (T-20, FR-12, AC-10)
//
// Sesión de escaneo en ráfaga: cola de productos, cada lectura se asigna
// al producto en turno y auto-avanza; duplicado pausa con tarjeta de
// conflicto (Omitir/Corregir) y el siguiente escaneo válido reanuda; al
// agotar la cola muestra un resumen y vuelve. Los códigos se inyectan por
// el camino de TECLADO (campo con Enter — lectores USB de pistola emiten
// teclado), que además es la degradación sin cámara (AC-07): las pruebas
// no dependen de cámara.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/sku_scan_session_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
  final Map<String, Map<String, dynamic>> ownersByCode = {};
  Object? updateError;
  final List<MapEntry<String, Map<String, dynamic>>> patched = [];

  @override
  Future<Map<String, dynamic>?> lookupProductByBarcode(String code) async {
    return ownersByCode[code];
  }

  @override
  Future<Map<String, dynamic>> updateProduct(
      String id, Map<String, dynamic> data) async {
    final err = updateError;
    if (err != null) throw err;
    patched.add(MapEntry(id, data));
    // Como el backend real: el código asignado ahora tiene dueño — una
    // relectura del mismo código contra OTRO producto daría conflicto.
    final code = (data['barcode'] ?? '').toString();
    if (code.isNotEmpty) {
      ownersByCode[code] = {'id': id, 'name': 'dueño-$id'};
    }
    return {'id': id, ...data};
  }
}

Map<String, dynamic> _p(String id, String name) => {
      'id': id,
      'name': name,
      'barcode': '',
      'price': 1000,
      'photo_url': '',
      'image_url': '',
    };

Future<void> _scanByKeyboard(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextField).first, code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  Widget wrap(Widget child) => MaterialApp(home: child);

  final queue = [_p('1', 'Arroz Diana'), _p('2', 'Panela'), _p('3', 'Aceite')];

  testWidgets('asigna al producto en turno y auto-avanza (AC-10)',
      (tester) async {
    final api = _FakeApi();
    final assigned = <String, String>{};
    await tester.pumpWidget(wrap(SkuScanSessionScreen(
      products: queue,
      apiOverride: api,
      keyboardOnly: true,
      onAssigned: (id, code) => assigned[id] = code,
    )));
    await tester.pump();

    // Banner del producto en turno.
    expect(find.text('Arroz Diana'), findsOneWidget);
    expect(find.textContaining('1 de 3'), findsOneWidget);

    await _scanByKeyboard(tester, '7702004003508');

    expect(api.patched.length, 1);
    expect(api.patched.first.key, '1');
    expect(api.patched.first.value['barcode'], '7702004003508');
    expect(assigned['1'], '7702004003508');
    // Auto-avance SIN diálogos intermedios: ya está en el producto 2.
    expect(find.text('Panela'), findsOneWidget);
    expect(find.textContaining('2 de 3'), findsOneWidget);
  });

  testWidgets('duplicado pausa con conflicto y el siguiente escaneo válido '
      'reanuda', (tester) async {
    final api = _FakeApi()
      ..ownersByCode['DUP-1'] = {'id': 'otro', 'name': 'Coca-Cola 350ml'};
    await tester.pumpWidget(wrap(SkuScanSessionScreen(
      products: queue,
      apiOverride: api,
      keyboardOnly: true,
    )));
    await tester.pump();

    await _scanByKeyboard(tester, 'DUP-1');

    // Pausa: tarjeta de conflicto con el dueño, nada asignado.
    expect(api.patched, isEmpty);
    expect(find.textContaining('Coca-Cola 350ml'), findsOneWidget);
    expect(find.text('Omitir'), findsOneWidget);
    expect(find.text('Corregir'), findsOneWidget);

    // El siguiente escaneo válido reanuda y asigna al MISMO producto.
    await _scanByKeyboard(tester, '7702004003508');
    expect(find.text('Omitir'), findsNothing);
    expect(api.patched.length, 1);
    expect(api.patched.first.key, '1');
    expect(find.textContaining('2 de 3'), findsOneWidget);
  });

  testWidgets('Omitir salta el producto en turno sin asignar', (tester) async {
    final api = _FakeApi()
      ..ownersByCode['DUP-1'] = {'id': 'otro', 'name': 'Coca-Cola 350ml'};
    await tester.pumpWidget(wrap(SkuScanSessionScreen(
      products: queue,
      apiOverride: api,
      keyboardOnly: true,
    )));
    await tester.pump();

    await _scanByKeyboard(tester, 'DUP-1');
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();

    expect(api.patched, isEmpty);
    expect(find.text('Panela'), findsOneWidget); // pasó al siguiente
    expect(find.textContaining('2 de 3'), findsOneWidget);
  });

  testWidgets('cola agotada → resumen y Volver cierra la sesión',
      (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(wrap(SkuScanSessionScreen(
      products: [_p('1', 'Arroz Diana'), _p('2', 'Panela')],
      apiOverride: api,
      keyboardOnly: true,
    )));
    await tester.pump();

    await _scanByKeyboard(tester, '1111');
    await _scanByKeyboard(tester, '2222');

    expect(api.patched.length, 2);
    expect(find.textContaining('2 códigos asignados'), findsOneWidget);

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(SkuScanSessionScreen), findsNothing);
  });

  testWidgets('cámara: relectura del MISMO código recién asignado se ignora '
      '(no conflicto falso, no doble asignación)', (tester) async {
    // Con cámara NATIVA el MobileScanner sigue detectando durante el flash
    // (~cada 250 ms). Si el tendero no retira la cámara, el mismo código
    // redispara contra el producto SIGUIENTE: sin el guard de _lastCode se
    // pintaba una tarjeta de conflicto falsa que rompía la ráfaga (FR-12).
    final api = _FakeApi();
    final detections = StreamController<String>();
    addTearDown(detections.close);
    await tester.pumpWidget(wrap(SkuScanSessionScreen(
      products: queue,
      apiOverride: api,
      keyboardOnly: true,
      detectionStream: detections.stream,
    )));
    await tester.pump();

    detections.add('7702004003508');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.patched.length, 1);
    expect(find.textContaining('2 de 3'), findsOneWidget);

    // Relectura inmediata del mismo encuadre: debe ignorarse por completo.
    detections.add('7702004003508');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.patched.length, 1); // sin doble asignación
    expect(find.text('Omitir'), findsNothing); // sin conflicto falso
    expect(find.textContaining('2 de 3'), findsOneWidget); // sigue en turno

    // Un código DISTINTO sí avanza la sesión con normalidad.
    detections.add('7702011223344');
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(api.patched.length, 2);
    expect(api.patched.last.key, '2');
    expect(find.textContaining('3 de 3'), findsOneWidget);
  });

  testWidgets('error de red NO marca el producto y ofrece Reintentar',
      (tester) async {
    final api = _FakeApi()
      ..updateError = const AppError(
        type: AppErrorType.network,
        message: 'No pudimos conectar.',
      );
    await tester.pumpWidget(wrap(SkuScanSessionScreen(
      products: [_p('1', 'Arroz Diana')],
      apiOverride: api,
      keyboardOnly: true,
    )));
    await tester.pump();

    await _scanByKeyboard(tester, '7702004003508');

    expect(api.patched, isEmpty);
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.textContaining('Arroz Diana'), findsWidgets);
    expect(find.text('Reintentar'), findsOneWidget);

    api.updateError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(api.patched.length, 1);
    expect(find.textContaining('1 código asignado'), findsOneWidget);
  });
}
