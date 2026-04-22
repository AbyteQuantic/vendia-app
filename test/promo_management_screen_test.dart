import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/screens/online_store/promo_management_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';

// ── Fake ApiService ───────────────────────────────────────────────────────────
//
// PromoManagementScreen only uses three methods of ApiService for the
// flows under test (fetchStoreSlug, fetchPromotions, updateStoreSlug).
// Subclassing and overriding just those keeps the test hermetic — no
// Dio, no network, no real AuthService calls. The parent constructor
// still requires an AuthService, but since none of the overridden
// methods touch `_auth.getToken()` (they skip Dio entirely) this is
// safe: AuthService() never hits flutter_secure_storage unless we ask
// it to.

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
        _wrap(PromoManagementScreen(apiService: fake)),
      );
      // Let the two async loaders settle.
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
    });

    testWidgets('muestra el empty state cuando no hay promos',
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
        _wrap(PromoManagementScreen(apiService: fake)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('promos_empty')), findsOneWidget);
      expect(find.text('Aún no tienes promociones'), findsOneWidget);
    });

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
        _wrap(PromoManagementScreen(apiService: fake)),
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
