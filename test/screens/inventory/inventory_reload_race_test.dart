// Auditoría 2026-07-10 — Mi Inventario: dos cargas en vuelo (cambio de sede
// mientras la carga inicial aún no responde, pull-to-refresh + reload al
// volver de una vista de curaduría) podían aplicarse FUERA DE ORDEN: la
// respuesta VIEJA (lenta) llegaba de última y pisaba la lista con los
// productos de la sede anterior — el inventario visible divergía del
// servidor. Mismo guard de secuencia que ya usa RetouchCompletionScreen
// (review HIGH-2): solo la respuesta de la request más NUEVA se aplica.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vendia_pos/models/branch.dart';
import 'package:vendia_pos/screens/inventory/manage_inventory_screen.dart';
import 'package:vendia_pos/services/api_service.dart';
import 'package:vendia_pos/services/auth_service.dart';
import 'package:vendia_pos/services/branch_provider.dart';
import 'package:vendia_pos/theme/app_theme.dart';

/// Cada fetchAllProducts devuelve un Future controlado a mano — permite
/// resolver las respuestas en el orden que la red real puede entregarlas.
class _SequencedApi extends ApiService {
  _SequencedApi() : super(AuthService());

  final List<Completer<List<Map<String, dynamic>>>> pending = [];

  @override
  Future<List<Map<String, dynamic>>> fetchAllProducts(
      {String? branchId, bool sellableOnly = false}) {
    final c = Completer<List<Map<String, dynamic>>>();
    pending.add(c);
    return c.future;
  }

  @override
  Future<Map<String, dynamic>> fetchRetouchSummary(
      {int page = 1, int perPage = 100}) async {
    return const {
      'eligible_count': 0,
      'active_batch': null,
      'review_items': <Map<String, dynamic>>[],
    };
  }
}

Map<String, dynamic> _p(String id, String name) => {
      'id': id,
      'name': name,
      'price': 1000,
      'stock': 5,
      'barcode': '111',
      'category': 'Bebidas',
      'photo_url': '',
      'image_url': '',
    };

Branch _branch(String id, String name, {bool isDefault = false}) => Branch(
      id: id,
      tenantId: 't1',
      name: name,
      isDefault: isDefault,
      isActive: true,
      createdAt: DateTime(2026),
    );

void main() {
  setUpAll(
      () => dotenv.testLoad(fileInput: 'API_BASE_URL=http://localhost:8080'));

  testWidgets('una respuesta VIEJA que llega tarde no pisa la lista de la '
      'sede nueva (guard de secuencia)', (tester) async {
    final api = _SequencedApi();
    final bp = BranchProvider()
      ..setBranches([
        _branch('b-a', 'Sede A', isDefault: true),
        _branch('b-b', 'Sede B'),
      ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<BranchProvider>.value(
        value: bp,
        child: MaterialApp(
          theme: AppTheme.light,
          home: ManageInventoryScreen(
            apiOverride: api,
            tenantIdOverride: 't1',
          ),
        ),
      ),
    );
    await tester.pump(); // initState → carga #1 (Sede A) en vuelo
    expect(api.pending.length, 1);

    // El tendero cambia de sede ANTES de que responda la carga inicial
    // (ventana real: la paginación completa de 500+ referencias tarda).
    bp.selectBranch(_branch('b-b', 'Sede B'));
    await tester.pump();
    expect(api.pending.length, 2); // carga #2 (Sede B) en vuelo

    // La carga #2 (sede nueva) responde PRIMERO.
    api.pending[1].complete([_p('2', 'Producto Sede B')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Producto Sede B'), findsOneWidget);

    // La carga #1 (sede VIEJA, lenta) llega de última: debe DESCARTARSE.
    api.pending[0].complete([_p('1', 'Producto Sede A')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Producto Sede B'), findsOneWidget,
        reason: 'la respuesta vieja no debe pisar la lista de la sede activa');
    expect(find.text('Producto Sede A'), findsNothing,
        reason: 'los productos de la sede anterior no deben reaparecer');
  });

  testWidgets('un error de una carga VIEJA no pisa la lista ya cargada por '
      'una request más nueva', (tester) async {
    final api = _SequencedApi();
    final bp = BranchProvider()
      ..setBranches([
        _branch('b-a', 'Sede A', isDefault: true),
        _branch('b-b', 'Sede B'),
      ]);

    await tester.pumpWidget(
      ChangeNotifierProvider<BranchProvider>.value(
        value: bp,
        child: MaterialApp(
          theme: AppTheme.light,
          home: ManageInventoryScreen(
            apiOverride: api,
            tenantIdOverride: 't1',
          ),
        ),
      ),
    );
    await tester.pump();
    bp.selectBranch(_branch('b-b', 'Sede B'));
    await tester.pump();
    expect(api.pending.length, 2);

    api.pending[1].complete([_p('2', 'Producto Sede B')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Producto Sede B'), findsOneWidget);

    // La carga vieja FALLA tarde (timeout): no debe pintar el error sobre
    // la lista sana de la sede activa.
    api.pending[0].completeError(Exception('timeout'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Producto Sede B'), findsOneWidget);
    expect(find.text('Error al cargar inventario'), findsNothing);
  });
}
