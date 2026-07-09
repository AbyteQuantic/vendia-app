// Spec: specs/102-completar-categorias-inventario/spec.md
//
// CategoryCompletionScreen: carga sugerencias de IA (endpoint Spec 078) y
// agrupa por categoría sugerida; los sin sugerencia (o con la IA caída) van
// al grupo "Por clasificar" en modo manual. Aplicar por tarjeta / por grupo /
// todas (con confirmación única) escribe `category` vía updateProduct y la
// tarjeta sale SOLO con 2xx; fallo de red → permanece + Reintentar (el
// contador nunca miente). La corrección manual siempre gana a la IA y las
// categorías nuevas se normalizan contra las existentes (Spec 068).

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/category_completion_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/app_error.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/theme/app_theme.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  /// Respuesta simulada del endpoint de sugerencias [{id, name, suggested}].
  List<Map<String, dynamic>> suggestions = [];
  Object? suggestError;
  List<String> existingCategories = [];

  /// Error a lanzar en updateProduct por id (null = éxito).
  final Map<String, Object> updateErrors = {};
  final List<MapEntry<String, Map<String, dynamic>>> patched = [];

  @override
  Future<List<Map<String, dynamic>>> suggestProductCategories() async {
    final err = suggestError;
    if (err != null) throw err;
    return suggestions;
  }

  @override
  Future<List<String>> fetchProductCategories() async => existingCategories;

  @override
  Future<Map<String, dynamic>> updateProduct(
      String id, Map<String, dynamic> data) async {
    final err = updateErrors[id];
    if (err != null) throw err;
    patched.add(MapEntry(id, data));
    return {'id': id, ...data};
  }
}

Map<String, dynamic> _p(String id, String name) => {
      'id': id,
      'name': name,
      'category': '',
      'price': 2500,
      'photo_url': '',
      'image_url': '',
    };

Map<String, dynamic> _s(String id, String name, String suggested) =>
    {'id': id, 'name': name, 'suggested': suggested};

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  // Theme REAL de la app: el theme legacy de botones (64dp/22px) queda bajo
  // prueba y la tarjeta compacta no puede regresar a botones gigantes.
  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light, home: child);

  Future<void> pumpLoaded(WidgetTester tester, _FakeApi api,
      List<Map<String, dynamic>> products) async {
    await tester.pumpWidget(wrap(CategoryCompletionScreen(
      apiOverride: api,
      products: products,
    )));
    await tester.pump();
    await tester.pump();
  }

  group('carga y agrupación (FR-03, FR-09)', () {
    testWidgets('agrupa por categoría sugerida con encabezado nombre+conteo '
        'y botón Aplicar grupo (AC-02)', (tester) async {
      final api = _FakeApi()
        ..suggestions = [
          _s('1', 'Coca-Cola', 'Bebidas'),
          _s('2', 'Jugo Hit', 'Bebidas'),
          _s('3', 'Jabón Rey', 'Aseo'),
        ];
      await pumpLoaded(tester, api,
          [_p('1', 'Coca-Cola'), _p('2', 'Jugo Hit'), _p('3', 'Jabón Rey')]);

      expect(find.text('Aseo (1)'), findsOneWidget);
      expect(find.text('Bebidas (2)'), findsOneWidget);
      expect(find.text('Aplicar grupo'), findsNWidgets(2));
      expect(find.text('0 de 3 organizados'), findsOneWidget);
      // Cada tarjeta muestra su sugerencia editable (chip tocable).
      expect(find.text('Bebidas'), findsNWidgets(2));
      expect(find.text('Aseo'), findsOneWidget);
    });

    testWidgets('los productos sin sugerencia van al grupo "Por clasificar" '
        'sin Aplicar grupo', (tester) async {
      final api = _FakeApi()
        ..suggestions = [_s('1', 'Coca-Cola', 'Bebidas')];
      await pumpLoaded(
          tester, api, [_p('1', 'Coca-Cola'), _p('2', 'Cosa rara')]);

      expect(find.text('Bebidas (1)'), findsOneWidget);
      expect(find.text('Por clasificar (1)'), findsOneWidget);
      // Solo el grupo con sugerencia tiene botón de aplicar.
      expect(find.text('Aplicar grupo'), findsOneWidget);
      expect(find.text('Elegir categoría'), findsOneWidget);
    });

    testWidgets('IA caída → banner suave y modo manual sin bloqueo (AC-05)',
        (tester) async {
      final api = _FakeApi()
        ..suggestError = const AppError(
            type: AppErrorType.server, message: 'IA no disponible');
      await pumpLoaded(
          tester, api, [_p('1', 'Coca-Cola'), _p('2', 'Panela')]);

      expect(find.textContaining('IA no está disponible'), findsOneWidget);
      expect(find.text('Por clasificar (2)'), findsOneWidget);
      expect(find.text('Elegir categoría'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('aplicar (FR-04, FR-05, AC-03)', () {
    testWidgets('Aplicar por tarjeta escribe la categoría y la tarjeta sale '
        'solo con 2xx', (tester) async {
      final api = _FakeApi()
        ..suggestions = [
          _s('1', 'Coca-Cola', 'Bebidas'),
          _s('2', 'Panela', 'Abarrotes'),
        ];
      await pumpLoaded(tester, api, [_p('1', 'Coca-Cola'), _p('2', 'Panela')]);

      // Grupos alfabéticos: "Abarrotes" (Panela) va primero.
      await tester.tap(find.text('Aplicar').first);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.length, 1);
      expect(api.patched.first.key, '2');
      expect(api.patched.first.value, {'category': 'Abarrotes'});
      expect(find.text('Panela'), findsNothing); // la tarjeta salió
      expect(find.text('1 de 2 organizados'), findsOneWidget);
    });

    testWidgets('Aplicar grupo con confirmación única aplica a todo el grupo',
        (tester) async {
      final api = _FakeApi()
        ..suggestions = [
          _s('1', 'Coca-Cola', 'Bebidas'),
          _s('2', 'Jugo Hit', 'Bebidas'),
          _s('3', 'Jabón Rey', 'Aseo'),
        ];
      await pumpLoaded(tester, api,
          [_p('1', 'Coca-Cola'), _p('2', 'Jugo Hit'), _p('3', 'Jabón Rey')]);

      // "Bebidas" va después de "Aseo" (alfabético) → segundo botón.
      await tester.tap(find.text('Aplicar grupo').last);
      await tester.pumpAndSettle();
      expect(find.text('Sí, aplicar'), findsOneWidget); // confirmación
      await tester.tap(find.text('Sí, aplicar'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.length, 2);
      expect(api.patched.map((e) => e.value['category']).toSet(), {'Bebidas'});
      expect(find.text('Bebidas (2)'), findsNothing);
      expect(find.text('Aseo (1)'), findsOneWidget); // el otro grupo sigue
      expect(find.text('2 de 3 organizados'), findsOneWidget);
    });

    testWidgets('Aplicar todas (N) vacía la lista y muestra el estado '
        'celebratorio (AC-03)', (tester) async {
      final api = _FakeApi()
        ..suggestions = [
          _s('1', 'Coca-Cola', 'Bebidas'),
          _s('2', 'Jabón Rey', 'Aseo'),
        ];
      await pumpLoaded(
          tester, api, [_p('1', 'Coca-Cola'), _p('2', 'Jabón Rey')]);

      expect(find.text('Aplicar todas (2)'), findsOneWidget);
      await tester.tap(find.text('Aplicar todas (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sí, aplicar'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.length, 2);
      expect(find.text('¡Todo organizado!'), findsOneWidget);
    });

    testWidgets('los "Por clasificar" no entran en Aplicar todas (N)',
        (tester) async {
      final api = _FakeApi()
        ..suggestions = [_s('1', 'Coca-Cola', 'Bebidas')];
      await pumpLoaded(
          tester, api, [_p('1', 'Coca-Cola'), _p('2', 'Cosa rara')]);

      expect(find.text('Aplicar todas (1)'), findsOneWidget);
    });
  });

  group('edición manual (AC-04, FR-06)', () {
    testWidgets('corregir la sugerencia por tarjeta: la mía gana a la IA',
        (tester) async {
      final api = _FakeApi()
        ..suggestions = [_s('1', 'Kumis', 'Bebidas')];
      await pumpLoaded(tester, api, [_p('1', 'Kumis')]);

      // Toca el chip de sugerencia → selector → escribe una nueva.
      await tester.tap(find.text('Bebidas'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Nueva categoría'), 'Lácteos');
      await tester.tap(find.text('Usar esta categoría'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aplicar').first);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.single.value, {'category': 'Lácteos'});
    });

    testWidgets('el selector ofrece las categorías existentes del tenant',
        (tester) async {
      final api = _FakeApi()
        ..existingCategories = ['Bebidas', 'Aseo']
        ..suggestions = [];
      await pumpLoaded(tester, api, [_p('1', 'Jabón Rey')]);

      await tester.tap(find.text('Elegir categoría'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aseo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aplicar').first);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.single.value, {'category': 'Aseo'});
    });

    testWidgets('categoría nueva duplicada con otra capitalización se '
        'normaliza a la existente (caso borde Spec 068)', (tester) async {
      final api = _FakeApi()
        ..existingCategories = ['Bebidas']
        ..suggestions = [];
      await pumpLoaded(tester, api, [_p('1', 'Kumis')]);

      await tester.tap(find.text('Elegir categoría'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Nueva categoría'), 'bebidas');
      await tester.tap(find.text('Usar esta categoría'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aplicar').first);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // No crear "Bebidas" y "bebidas": reutiliza la grafía existente.
      expect(api.patched.single.value, {'category': 'Bebidas'});
    });
  });

  group('fallos honestos (AC-07, casos borde)', () {
    testWidgets('fallo de red → la tarjeta permanece + Reintentar; al volver '
        'la señal, aplica', (tester) async {
      final api = _FakeApi()
        ..suggestions = [
          _s('1', 'Coca-Cola', 'Bebidas'),
          _s('2', 'Jugo Hit', 'Bebidas'),
        ]
        ..updateErrors['2'] = const AppError(
            type: AppErrorType.network, message: 'No pudimos conectar.');
      await pumpLoaded(
          tester, api, [_p('1', 'Coca-Cola'), _p('2', 'Jugo Hit')]);

      await tester.tap(find.text('Aplicar grupo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sí, aplicar'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // Resumen honesto: 1 guardado, 1 fallido que sigue en la lista.
      expect(api.patched.length, 1);
      expect(find.text('Jugo Hit'), findsOneWidget);
      // Banner persistente + resumen honesto (toast) — ambos avisan.
      expect(find.textContaining('no se guard'), findsWidgets);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('1 de 2 organizados'), findsOneWidget);

      api.updateErrors.clear();
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.length, 2);
      expect(find.text('¡Todo organizado!'), findsOneWidget);
    });

    testWidgets('producto eliminado desde otro dispositivo (404) → se '
        'informa y la tarjeta se retira', (tester) async {
      final api = _FakeApi()
        ..suggestions = [_s('1', 'Coca-Cola', 'Bebidas')]
        ..updateErrors['1'] = const AppError(
            type: AppErrorType.validation,
            message: 'No existe.',
            statusCode: 404);
      await pumpLoaded(tester, api, [_p('1', 'Coca-Cola')]);

      await tester.tap(find.text('Aplicar').first);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched, isEmpty);
      expect(find.textContaining('ya no existe'), findsOneWidget);
      expect(find.text('¡Todo organizado!'), findsOneWidget);
    });
  });

  group('selección múltiple (FR-10)', () {
    testWidgets('marcar varios y asignarles UNA categoría en una sola acción',
        (tester) async {
      final api = _FakeApi()
        ..existingCategories = ['Aseo']
        ..suggestions = [];
      await pumpLoaded(tester, api,
          [_p('1', 'Jabón Rey'), _p('2', 'Límpido'), _p('3', 'Arroz')]);

      await tester.tap(find.text('Seleccionar'));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(3));

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      expect(find.text('Asignar categoría a 2'), findsOneWidget);

      await tester.tap(find.text('Asignar categoría a 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aseo'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(api.patched.length, 2);
      expect(api.patched.map((e) => e.key).toSet(), {'1', '2'});
      expect(api.patched.map((e) => e.value['category']).toSet(), {'Aseo'});
      expect(find.text('Arroz'), findsOneWidget); // el no marcado sigue
    });
  });

  group('UI a 360dp', () {
    testWidgets('nombres y categorías largas: cero overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = _FakeApi()
        ..suggestions = [
          _s('1', 'Chocolatina de maní con leche entera edición especial',
              'Dulces Y Golosinas Importadas'),
        ];
      await pumpLoaded(tester, api, [
        _p('1', 'Chocolatina de maní con leche entera edición especial'),
        _p('2', 'Producto misterioso sin ninguna pista de categoría posible'),
      ]);

      expect(tester.takeException(), isNull);

      // Selector abierto tampoco desborda.
      await tester.tap(find.text('Elegir categoría'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
