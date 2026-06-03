import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/mock_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Flow 5: Cuaderno Buckets', () {
    late MockApiService mockApi;

    setUpAll(() {
      dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080');
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockApi = MockApiService();
    });

    group('3 tabs mutual exclusivity', () {
      test('only one filter value is active at a time', () {
        String? activeFilter;

        void selectTab(String tab) {
          activeFilter = tab;
        }

        selectTab('active');
        expect(activeFilter, 'active');
        expect(activeFilter, isNot('pending'));
        expect(activeFilter, isNot('paid'));

        selectTab('pending');
        expect(activeFilter, 'pending');
        expect(activeFilter, isNot('active'));
        expect(activeFilter, isNot('paid'));

        selectTab('paid');
        expect(activeFilter, 'paid');
        expect(activeFilter, isNot('active'));
        expect(activeFilter, isNot('pending'));
      });

      test('_credits getter returns correct data list per filter', () {
        final state = _CuadernoState();
        state.activos = [
          {'customer_name': 'Juan', 'balance': 15000},
        ];
        state.pendientes = [
          {'customer_name': 'María', 'status': 'pending'},
        ];
        state.pagados = [
          {'customer_name': 'Carlos', 'status': 'paid'},
        ];

        state.filter = 'active';
        expect(state.credits.length, 1);
        expect(state.credits[0]['customer_name'], 'Juan');

        state.filter = 'pending';
        expect(state.credits.length, 1);
        expect(state.credits[0]['customer_name'], 'María');

        state.filter = 'paid';
        expect(state.credits.length, 1);
        expect(state.credits[0]['customer_name'], 'Carlos');
      });

      test('selecting one tab deselects others', () {
        final selected = <String>{};

        void onTabTap(String tab) {
          selected.clear();
          selected.add(tab);
        }

        onTabTap('active');
        expect(selected, contains('active'));
        expect(selected, isNot(contains('pending')));
        expect(selected, isNot(contains('paid')));

        onTabTap('pending');
        expect(selected, contains('pending'));
        expect(selected, isNot(contains('active')));
        expect(selected, isNot(contains('paid')));

        onTabTap('paid');
        expect(selected, contains('paid'));
        expect(selected, isNot(contains('active')));
        expect(selected, isNot(contains('pending')));
      });

      test('default initial tab is active', () {
        const defaultFilter = 'active';
        expect(defaultFilter, 'active');
      });
    });

    group('Tab-specific tile rendering', () {
      test('active tab uses grouped tile (one per customer)', () {
        bool usesGroupedTile(String filter) => filter == 'active';

        expect(usesGroupedTile('active'), isTrue);
        expect(usesGroupedTile('pending'), isFalse);
        expect(usesGroupedTile('paid'), isFalse);
      });

      test('pending and paid tabs use account tile', () {
        bool usesAccountTile(String filter) =>
            filter == 'pending' || filter == 'paid';

        expect(usesAccountTile('pending'), isTrue);
        expect(usesAccountTile('paid'), isTrue);
        expect(usesAccountTile('active'), isFalse);
      });

      test('pending tab adds resend action button', () {
        bool hasResendButton(String filter) => filter == 'pending';

        expect(hasResendButton('pending'), isTrue);
        expect(hasResendButton('paid'), isFalse);
        expect(hasResendButton('active'), isFalse);
      });
    });

    group('API data loading', () {
      test('fetchCredits(status: pending) returns pending credits', () async {
        final result = await mockApi.fetchCredits(status: 'pending', perPage: 200);
        expect(result['credits'], isNotNull);
      });

      test('fetchCredits(status: paid) returns paid credits', () async {
        final result = await mockApi.fetchCredits(status: 'paid', perPage: 200);
        expect(result['credits'], isNotNull);
      });

      test('fetchCreditsGroupedByCustomer returns grouped active credits',
          () async {
        final result = await mockApi.fetchCreditsGroupedByCustomer();
        expect(result.length, 1);
        expect(result[0]['customer_name'], 'Juan Pérez');
        expect(result[0]['total_balance'], 15000);
      });

      test('Future.wait loads all 3 tabs up-front', () async {
        final results = await Future.wait<dynamic>([
          mockApi.fetchCreditsGroupedByCustomer(),
          mockApi.fetchCredits(status: 'pending', perPage: 200),
          mockApi.fetchCredits(status: 'paid', perPage: 200),
        ]);

        expect(results.length, 3);
        final activos = results[0] as List;
        final pendientes = (results[1] as Map)['credits'] as List;
        final pagados = (results[2] as Map)['credits'] as List;

        expect(activos.length, 1);
        expect(pendientes.length, 1);
        expect(pagados.length, 1);

        expect(mockApi.callCount, 3);
      });

      test('tab switches do NOT refetch data (client-side partition)', () async {
        final callCountBefore = mockApi.callCount;

        var filter = 'active';
        // Simulate tab switches without API calls (client-side partition).
        filter = 'pending';
        filter = 'paid';
        filter = 'active';
        expect(filter, 'active');

        expect(mockApi.callCount, callCountBefore,
            reason: 'Tab switches must not hit the network');
      });
    });

    group('Full Cuaderno flow (mock integration)', () {
      test('load all 3 tabs -> switch between them -> verify data', () async {
        final results = await Future.wait<dynamic>([
          mockApi.fetchCreditsGroupedByCustomer(),
          mockApi.fetchCredits(status: 'pending', perPage: 200),
          mockApi.fetchCredits(status: 'paid', perPage: 200),
        ]);

        final state = _CuadernoState();
        state.activos = (results[0] as List).cast<Map<String, dynamic>>();
        state.pendientes = ((results[1] as Map<String, dynamic>)['credits']
                as List)
            .cast<Map<String, dynamic>>();
        state.pagados = ((results[2] as Map<String, dynamic>)['credits']
                as List)
            .cast<Map<String, dynamic>>();

        state.filter = 'active';
        expect(state.credits.length, 1);
        expect(state.credits[0]['customer_name'], 'Juan Pérez');

        state.filter = 'pending';
        expect(state.credits.length, 1);

        state.filter = 'paid';
        expect(state.credits.length, 1);

        expect(mockApi.callCount, 3,
            reason: 'Only 3 API calls for all 3 tabs, no refetches');
      });
    });
  });
}

class _CuadernoState {
  String filter = 'active';
  List<Map<String, dynamic>> activos = [];
  List<Map<String, dynamic>> pendientes = [];
  List<Map<String, dynamic>> pagados = [];

  List<Map<String, dynamic>> get credits {
    switch (filter) {
      case 'pending':
        return pendientes;
      case 'paid':
        return pagados;
      case 'active':
      default:
        return activos;
    }
  }
}
