// Spec: specs/101-retocar-fotos-inventario/spec.md (T-20/T-21, FR-01, FR-02,
// FR-03, AC-01, AC-02, AC-07)
//
// Predicado público "foto sin retocar": tiene foto propia (URL en
// `products/<tenantId>/`) que NO pasó por Mejorar con IA (`-enhanced`), no es
// generada (`-generated`), no está marcada `is_ai_enhanced` ni es muestra IA
// (`photo_is_sample`). El chip "Fotos sin retocar (N)" cuenta al cargar y
// navega a la vista dedicada; con revisión pendiente (summary del backend)
// cambia a "Fotos por revisar (N)".

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';
import 'package:vendia_pos/screens/inventory/retouch_completion_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

class _FakeApi extends ApiService {
  _FakeApi(this._products, {Map<String, dynamic>? summary})
      : _summary = summary ??
            const {
              'eligible_count': 0,
              'active_batch': null,
              'review_items': <Map<String, dynamic>>[],
            },
        super(AuthService());

  final List<Map<String, dynamic>> _products;
  final Map<String, dynamic> _summary;
  int fetchCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchAllProducts(
      {String? branchId, bool sellableOnly = false}) async {
    fetchCalls++;
    return _products;
  }

  @override
  Future<Map<String, dynamic>> fetchRetouchSummary() async => _summary;
}

Map<String, dynamic> _p(
  String id,
  String name, {
  String photoUrl = '',
  String imageUrl = '',
  bool aiEnhanced = false,
  bool sample = false,
}) =>
    {
      'id': id,
      'name': name,
      'barcode': '111$id',
      'price': 2500,
      'stock': 3,
      'photo_url': photoUrl,
      'image_url': imageUrl,
      if (aiEnhanced) 'is_ai_enhanced': true,
      if (sample) 'photo_is_sample': true,
    };

const _t = 'tenant-1';
const _raw1 = 'https://r2.vendia.store/products/$_t/aaa.jpg';
const _raw2 = 'https://r2.vendia.store/products/$_t/bbb.png?v=2';
const _raw3 = 'https://r2.vendia.store/products/$_t/ccc.jpg';
const _enhanced = 'https://r2.vendia.store/products/$_t/ddd-enhanced.jpg';
const _generated = 'https://r2.vendia.store/products/$_t/eee-generated.png';
const _catalog = 'https://r2.vendia.store/catalog/7702004003508.jpg';

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  group('isPhotoUnretouched (AC-01, FR-01/FR-02)', () {
    test('foto propia cruda del tenant cuenta', () {
      expect(
          isPhotoUnretouched(_p('1', 'Arroz', photoUrl: _raw1), tenantId: _t),
          isTrue);
    });

    test('foto cruda en image_url (sin photo_url) cuenta', () {
      expect(
          isPhotoUnretouched(_p('1', 'Arroz', imageUrl: _raw2), tenantId: _t),
          isTrue);
    });

    test('sin foto NO cuenta (eso es "Sin imagen")', () {
      expect(isPhotoUnretouched(_p('1', 'Arroz'), tenantId: _t), isFalse);
    });

    test('URL -enhanced NO cuenta', () {
      expect(
          isPhotoUnretouched(_p('1', 'Arroz', photoUrl: _enhanced),
              tenantId: _t),
          isFalse);
    });

    test('URL -generated NO cuenta', () {
      expect(
          isPhotoUnretouched(_p('1', 'Arroz', photoUrl: _generated),
              tenantId: _t),
          isFalse);
    });

    test('foto del catálogo compartido NO cuenta', () {
      expect(
          isPhotoUnretouched(_p('1', 'Arroz', photoUrl: _catalog),
              tenantId: _t),
          isFalse);
    });

    test('foto de OTRO tenant NO cuenta (aislamiento)', () {
      expect(
          isPhotoUnretouched(
              _p('1', 'Arroz',
                  photoUrl: 'https://r2.vendia.store/products/otro/x.jpg'),
              tenantId: _t),
          isFalse);
    });

    test('is_ai_enhanced=true NO cuenta aunque la URL parezca cruda', () {
      expect(
          isPhotoUnretouched(
              _p('1', 'Arroz', photoUrl: _raw1, aiEnhanced: true),
              tenantId: _t),
          isFalse);
    });

    test('photo_is_sample=true NO cuenta (muestra IA de plato)', () {
      expect(
          isPhotoUnretouched(_p('1', 'Plato', photoUrl: _raw1, sample: true),
              tenantId: _t),
          isFalse);
    });

    test('sin tenantId conocido NO cuenta (conservador)', () {
      expect(isPhotoUnretouched(_p('1', 'Arroz', photoUrl: _raw1),
              tenantId: ''),
          isFalse);
    });

    test('AC-01: 3 crudas + 1 mejorada + 1 catálogo + 1 muestra → 3', () {
      final products = [
        _p('1', 'Arroz', photoUrl: _raw1),
        _p('2', 'Panela', photoUrl: _raw2),
        _p('3', 'Lenteja', photoUrl: _raw3),
        _p('4', 'Coca', photoUrl: _enhanced, aiEnhanced: true),
        _p('5', 'Jabón', photoUrl: _catalog),
        _p('6', 'Bandeja', photoUrl: _raw1, sample: true),
      ];
      expect(
          products.where((p) => isPhotoUnretouched(p, tenantId: _t)).length,
          3);
    });
  });

  group('chip en Mi Inventario', () {
    final products = [
      _p('1', 'Arroz', photoUrl: _raw1),
      _p('2', 'Panela', photoUrl: _raw2),
      _p('3', 'Coca', photoUrl: _enhanced, aiEnhanced: true),
    ];

    testWidgets('muestra "Fotos sin retocar (N)" con objetivo táctil ≥44dp',
        (tester) async {
      final api = _FakeApi(products);
      await tester.pumpWidget(MaterialApp(
          home: ManageInventoryScreen(apiOverride: api, tenantIdOverride: _t)));
      await tester.pump();
      await tester.pump();

      final chip = find.widgetWithText(ActionChip, 'Fotos sin retocar (2)');
      expect(chip, findsOneWidget);
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    });

    testWidgets('AC-07: sin fotos crudas el chip no aparece', (tester) async {
      final api = _FakeApi(
          [_p('3', 'Coca', photoUrl: _enhanced, aiEnhanced: true)]);
      await tester.pumpWidget(MaterialApp(
          home: ManageInventoryScreen(apiOverride: api, tenantIdOverride: _t)));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Fotos sin retocar'), findsNothing);
      expect(find.textContaining('Fotos por revisar'), findsNothing);
    });

    testWidgets(
        'con ready_for_review > 0 el chip cambia a "Fotos por revisar (N)"',
        (tester) async {
      final api = _FakeApi(products, summary: {
        'eligible_count': 2,
        'active_batch': {
          'id': 'b1',
          'status': 'running',
          'queued': 1,
          'processed': 3,
          'failed': 0,
          'ready_for_review': 3,
        },
        'review_items': [
          {
            'item_id': 'i1',
            'product_id': '1',
            'name': 'Arroz',
            'original_url': _raw1,
            'candidate_url': _enhanced,
          },
        ],
      });
      await tester.pumpWidget(MaterialApp(
          home: ManageInventoryScreen(apiOverride: api, tenantIdOverride: _t)));
      await tester.pump();
      await tester.pump();

      expect(find.text('Fotos por revisar (3)'), findsOneWidget);
      expect(find.textContaining('Fotos sin retocar'), findsNothing);
    });

    testWidgets(
        'AC-02: tocar el chip navega a RetouchCompletionScreen con la lista '
        'prefiltrada y al volver recarga (FR-07)', (tester) async {
      final api = _FakeApi(products);
      await tester.pumpWidget(MaterialApp(
          home: ManageInventoryScreen(apiOverride: api, tenantIdOverride: _t)));
      await tester.pump();
      await tester.pump();
      final callsBefore = api.fetchCalls;

      await tester.tap(find.text('Fotos sin retocar (2)'));
      await tester.pumpAndSettle();

      expect(find.byType(RetouchCompletionScreen), findsOneWidget);
      final screen = tester.widget<RetouchCompletionScreen>(
          find.byType(RetouchCompletionScreen));
      expect(screen.products.length, 2);
      expect(screen.products.map((p) => p['name']),
          containsAll(['Arroz', 'Panela']));

      Navigator.of(tester.element(find.byType(RetouchCompletionScreen)))
          .pop();
      await tester.pumpAndSettle();
      expect(api.fetchCalls, greaterThan(callsBefore));
    });

    testWidgets('no desborda a 360dp con los tres contadores visibles',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = _FakeApi([
        _p('1', 'Arroz', photoUrl: _raw1),
        _p('2', 'Panela', photoUrl: _raw2),
        {..._p('7', 'Sin precio', photoUrl: _raw3), 'price': 0},
        {..._p('8', 'Sin sku'), 'barcode': ''},
      ]);
      await tester.pumpWidget(MaterialApp(
          home: ManageInventoryScreen(apiOverride: api, tenantIdOverride: _t)));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Fotos sin retocar'), findsOneWidget);
    });
  });
}
