import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/database/collections/local_product.dart';
import 'package:vendia_pos/screens/online_store/promo_management_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

// ── Fake ApiService ───────────────────────────────────────────────────────────
//
// PromoManagementScreen only uses a handful of ApiService methods for
// the flows under test (fetchStoreSlug, fetchPromotions,
// updateStoreSlug). Subclassing and overriding just those keeps the
// test hermetic — no Dio, no network, no real AuthService calls. The
// expiring-products flow is injected separately via
// `expiringLoader` / `seedProductsLoader` to avoid touching Isar.
class _FakeApi extends ApiService {
  _FakeApi({
    required this.slugResponse,
    required this.promotions,
  }) : super(AuthService());

  final Map<String, dynamic> slugResponse;
  final List<Map<String, dynamic>> promotions;

  @override
  Future<Map<String, dynamic>> fetchStoreSlug() async =>
      Map<String, dynamic>.from(slugResponse);

  @override
  Future<List<Map<String, dynamic>>> fetchPromotions() async =>
      List<Map<String, dynamic>>.from(promotions);

  @override
  Future<Map<String, dynamic>> updateStoreSlug(String slug) async =>
      {'slug': slug, 'public_url': 'https://example.com/$slug'};
}

Widget _wrap(Widget child) => MaterialApp(home: child);

/// Default loaders used by most tests — inventory is healthy and we
/// never push into Isar-backed seed resolution.
Future<List<Map<String, dynamic>>> _emptyExpiring() async => const [];
Future<List<LocalProduct>> _emptySeeds(List<Map<String, dynamic>> rows) async =>
    const [];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Seed dotenv so ApiService's constructor (which reads
    // ApiConfig.baseUrl) doesn't throw NotInitializedError.
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('PromoManagementScreen (datos reales)', () {
    testWidgets('muestra el link del catálogo y las promos reales',
        (tester) async {
      final fake = _FakeApi(
        slugResponse: const {
          'slug': 'tienda-don-pepe-a4x9',
          'base_url': 'https://vendia-admin.vercel.app',
          'public_url':
              'https://vendia-admin.vercel.app/tienda-don-pepe-a4x9',
        },
        promotions: const [
          {
            'id': 'p1',
            'name': 'Combo Perro + Jugo',
            'items': [
              {
                'name': 'Perro Caliente',
                'quantity': 1,
                'promo_price': 3500,
              },
              {
                'name': 'Jugo Hit',
                'quantity': 1,
                'promo_price': 2500,
              },
            ],
            'total_regular': 9000,
          },
        ],
      );

      await tester.pumpWidget(
        _wrap(PromoManagementScreen(
          apiService: fake,
          expiringLoader: _emptyExpiring,
          seedProductsLoader: _emptySeeds,
        )),
      );
      await tester.pumpAndSettle();

      // Catalog card renders the public URL so the user can share it.
      expect(find.byKey(const Key('catalog_card')), findsOneWidget);
      expect(
        find.text('https://vendia-admin.vercel.app/tienda-don-pepe-a4x9'),
        findsOneWidget,
      );

      // Edit + Share buttons are wired and enabled (they were disabled
      // while the slug was null during the initial frame).
      final editBtn = tester.widget<OutlinedButton>(
        find.byKey(const Key('btn_edit_slug')),
      );
      final shareBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_share_catalog')),
      );
      expect(editBtn.onPressed, isNotNull);
      expect(shareBtn.onPressed, isNotNull);

      // The real promotion name is rendered — NOT the old mocked
      // "Perro Caliente Sencillo" / "Hamburguesa Doble" / "Jugo Natural"
      // strings that used to live in this screen.
      expect(find.text('Combo Perro + Jugo'), findsOneWidget);
      expect(find.byKey(const Key('promos_list')), findsOneWidget);
      expect(find.byKey(const Key('promo_p1')), findsOneWidget);
      expect(find.byKey(const Key('share_p1')), findsOneWidget);

      // Old mocked copy must be gone — regression guard.
      expect(find.text('Perro Caliente Sencillo'), findsNothing);
      expect(find.text('Hamburguesa Doble'), findsNothing);
      expect(find.text('Jugo Natural'), findsNothing);

      // CTA principal (bottom-pinned) — debe existir y estar habilitado.
      expect(find.byKey(const Key('btn_create_promo')), findsOneWidget);
      expect(find.text('✨ Crear Nueva Promoción'), findsOneWidget);

      // Con promos e inventario sano no mostramos ninguna sugerencia
      // — sería ruido innecesario.
      expect(find.byKey(const Key('suggestion_expiring')), findsNothing);
      expect(find.byKey(const Key('suggestion_idea')), findsNothing);
    });

    testWidgets(
        'empty state educativo + sugerencia de IA cuando inventario sano y sin promos',
        (tester) async {
      final fake = _FakeApi(
        slugResponse: const {
          'slug': 'mi-tienda',
          'base_url': 'https://vendia-admin.vercel.app',
          'public_url': 'https://vendia-admin.vercel.app/mi-tienda',
        },
        promotions: const [],
      );

      await tester.pumpWidget(
        _wrap(PromoManagementScreen(
          apiService: fake,
          expiringLoader: _emptyExpiring,
          seedProductsLoader: _emptySeeds,
        )),
      );
      await tester.pumpAndSettle();

      // Empty state educativo — ya no es solo un ícono vacío.
      expect(find.byKey(const Key('promos_empty')), findsOneWidget);
      expect(find.text('¿Qué es una promoción?'), findsOneWidget);
      expect(
        find.text('Atrae más clientes a tu catálogo agrupando productos.'),
        findsOneWidget,
      );
      expect(find.text('Combo Desayuno'), findsOneWidget);

      // Sugerencia de IA (condición B): inventario sano y sin promos.
      expect(find.byKey(const Key('suggestion_idea')), findsOneWidget);
      expect(find.text('Sugerencia de IA'), findsOneWidget);

      // No debe aparecer la alerta de vencimientos.
      expect(find.byKey(const Key('suggestion_expiring')), findsNothing);
    });

    testWidgets(
        'muestra tarjeta de alerta cuando hay productos por vencer (condición A)',
        (tester) async {
      final fake = _FakeApi(
        slugResponse: const {
          'slug': 'mi-tienda',
          'base_url': 'https://vendia-admin.vercel.app',
          'public_url': 'https://vendia-admin.vercel.app/mi-tienda',
        },
        promotions: const [],
      );

      Future<List<Map<String, dynamic>>> expiring() async => const [
            {'id': 'prod-1', 'name': 'Leche', 'days_to_expire': 2},
            {'id': 'prod-2', 'name': 'Pan', 'days_to_expire': 1},
          ];

      await tester.pumpWidget(
        _wrap(PromoManagementScreen(
          apiService: fake,
          expiringLoader: expiring,
          seedProductsLoader: _emptySeeds,
        )),
      );
      await tester.pumpAndSettle();

      // Aparece la alerta naranja con el conteo correcto…
      expect(find.byKey(const Key('suggestion_expiring')), findsOneWidget);
      expect(find.byKey(const Key('btn_suggestion_expiring')), findsOneWidget);
      expect(
        find.textContaining('2 productos a punto de vencer'),
        findsOneWidget,
      );

      // …y en este caso NO mostramos el tip de IA (tendría prioridad
      // la alerta de pérdida inminente).
      expect(find.byKey(const Key('suggestion_idea')), findsNothing);
    });
  });

  group('PromoManagementScreen — edit slug modal', () {
    testWidgets('abre el modal para editar el link y valida el input',
        (tester) async {
      final fake = _FakeApi(
        slugResponse: const {
          'slug': 'mi-tienda',
          'base_url': 'https://vendia-admin.vercel.app',
          'public_url': 'https://vendia-admin.vercel.app/mi-tienda',
        },
        promotions: const [],
      );

      await tester.pumpWidget(
        _wrap(PromoManagementScreen(
          apiService: fake,
          expiringLoader: _emptyExpiring,
          seedProductsLoader: _emptySeeds,
        )),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_edit_slug')));
      await tester.pumpAndSettle();

      // The bottom sheet renders an input pre-filled with the slug.
      expect(find.byKey(const Key('slug_input')), findsOneWidget);
      expect(find.byKey(const Key('btn_save_slug')), findsOneWidget);

      // Clearing the field and saving must surface an inline
      // validation error (client-side, before hitting the network).
      await tester.enterText(find.byKey(const Key('slug_input')), 'ab');
      await tester.tap(find.byKey(const Key('btn_save_slug')));
      await tester.pump();
      expect(find.text('Debe tener al menos 3 caracteres.'), findsOneWidget);
    });
  });
}
