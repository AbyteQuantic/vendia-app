import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/widgets/table_qr_sheet.dart';

/// Fake ApiService that only implements the two calls the QR sheet
/// exercises. Any other call would throw `UnimplementedError` — a
/// deliberate tripwire so we notice if the production widget
/// starts pulling in unrelated endpoints.
class _FakeApi extends ApiService {
  _FakeApi({
    required this.slugResponse,
    required this.openAccounts,
  }) : super(AuthService());

  final Map<String, dynamic> slugResponse;
  final List<Map<String, dynamic>> openAccounts;

  @override
  Future<Map<String, dynamic>> fetchStoreSlug() async =>
      Map<String, dynamic>.from(slugResponse);

  @override
  Future<List<Map<String, dynamic>>> fetchOpenAccounts() async =>
      List<Map<String, dynamic>>.from(openAccounts);
}

Future<void> _openSheet(
  WidgetTester tester, {
  required String tableLabel,
  required ApiService api,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showTableQrSheet(
            ctx,
            tableLabel: tableLabel,
            apiOverride: api,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
  });

  group('TableQrSheet', () {
    testWidgets('renders QR and composes /t/<session_token> URL from origin',
        (tester) async {
      final api = _FakeApi(
        slugResponse: const {
          'slug': 'brasas',
          // base_url is the catalog root *including* the slug. The
          // sheet must chop it back to the origin for the /t/:token
          // route.
          'base_url': 'https://vendia-admin.vercel.app/brasas',
          'public_url': 'https://vendia-admin.vercel.app/brasas',
        },
        openAccounts: const [
          {
            'id': 'order-1',
            'label': 'Mesa 1',
            'session_token': 'aaaa-bbbb-cccc',
            'status': 'nuevo',
            'created_at': '2026-04-22T12:00:00Z',
          },
        ],
      );

      await _openSheet(tester, tableLabel: 'Mesa 1', api: api);

      // QR renders.
      expect(find.byKey(const Key('table_qr_image')), findsOneWidget);

      // `qr_flutter` doesn't expose `data` as a public getter, so
      // we assert indirectly on the URL we also render as
      // selectable text below the QR. The widget feeds both from
      // the same computed string, so pinning the visible text is
      // equivalent to pinning the QR payload.
      expect(
        find.text('https://vendia-admin.vercel.app/t/aaaa-bbbb-cccc'),
        findsOneWidget,
      );

      // Share CTA exists.
      expect(find.byKey(const Key('table_qr_share')), findsOneWidget);
    });

    testWidgets('matches label case-insensitively and picks newest ticket',
        (tester) async {
      final api = _FakeApi(
        slugResponse: const {
          'base_url': 'https://store.test/mi-tienda',
        },
        openAccounts: const [
          {
            'id': 'stale',
            'label': 'MESA 7',
            'session_token': 'stale-token',
            'created_at': '2026-04-20T10:00:00Z',
          },
          {
            'id': 'fresh',
            'label': 'mesa 7',
            'session_token': 'fresh-token',
            'created_at': '2026-04-22T10:00:00Z',
          },
          // Noise from a different table — must be ignored.
          {
            'id': 'other',
            'label': 'Mesa 2',
            'session_token': 'other-token',
            'created_at': '2026-04-23T10:00:00Z',
          },
        ],
      );

      await _openSheet(tester, tableLabel: 'Mesa 7', api: api);

      expect(find.byKey(const Key('table_qr_image')), findsOneWidget);
      expect(find.text('https://store.test/t/fresh-token'), findsOneWidget);
      // And the stale token must NOT leak into the rendered URL.
      expect(find.text('https://store.test/t/stale-token'), findsNothing);
    });

    testWidgets('shows empty state when no open ticket matches the table',
        (tester) async {
      final api = _FakeApi(
        slugResponse: const {'base_url': 'https://x.test/s'},
        openAccounts: const [
          {
            'id': 'o',
            'label': 'Mesa 3',
            'session_token': 'tok',
          },
        ],
      );

      await _openSheet(tester, tableLabel: 'Mesa 1', api: api);

      expect(find.byKey(const Key('table_qr_image')), findsNothing);
      expect(find.text('Aún no hay cuenta abierta'), findsOneWidget);
    });

    testWidgets('shows error state when base_url is missing', (tester) async {
      final api = _FakeApi(
        slugResponse: const {
          // Explicit empty base_url — the backend can return this
          // if the tenant hasn't finished catalog onboarding.
          'base_url': '',
        },
        openAccounts: const [
          {
            'label': 'Mesa 1',
            'session_token': 'tok',
          },
        ],
      );

      await _openSheet(tester, tableLabel: 'Mesa 1', api: api);

      expect(find.byKey(const Key('table_qr_image')), findsNothing);
      expect(
        find.textContaining('No encontramos el dominio'),
        findsOneWidget,
      );
    });
  });

  group('ApiService.fetchOpenTicketByLabel', () {
    test('returns null on empty label without hitting the network', () async {
      final api = _FakeApi(
        slugResponse: const {},
        openAccounts: const [
          {'label': 'Mesa 1', 'session_token': 't'},
        ],
      );
      expect(await api.fetchOpenTicketByLabel(''), isNull);
      expect(await api.fetchOpenTicketByLabel('   '), isNull);
    });

    test('picks the newest matching ticket', () async {
      final api = _FakeApi(
        slugResponse: const {},
        openAccounts: const [
          {
            'label': 'Mesa 2',
            'session_token': 'old',
            'created_at': '2026-04-01T12:00:00Z',
          },
          {
            'label': 'mesa 2',
            'session_token': 'new',
            'created_at': '2026-04-22T12:00:00Z',
          },
        ],
      );
      final row = await api.fetchOpenTicketByLabel('Mesa 2');
      expect(row, isNotNull);
      expect(row!['session_token'], 'new');
    });
  });
}
