// Spec: specs/041-catalogo-dinamico-modulos-tipos/spec.md
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendia_pos/services/catalog_service.dart';

Map<String, dynamic> _catalogJson({String version = 'v1', int modules = 2}) => {
      'modules': List.generate(
          modules,
          (i) => {
                'id': 'm$i',
                'key': 'mod$i',
                'name': 'Módulo $i',
                'category': 'vender',
                'render_type': 'native',
                'active': true,
                'sort_order': i,
              }),
      'types': [
        {'value': 'tienda_barrio', 'label': 'Tienda de Barrio', 'active': true}
      ],
      'relations': [],
      'overrides': [],
      'version': version,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('refresh guarda el catálogo y cached() lo devuelve', () async {
    final svc = CatalogService(
      fetcher: ({String? etag}) async =>
          (data: _catalogJson(), etag: '"abc"', notModified: false),
    );
    final c = await svc.refresh();
    expect(c, isNotNull);
    expect(c!.modules.length, 2);

    final fromCache = await svc.cached();
    expect(fromCache!.modules.length, 2);
    expect(fromCache.types.first.label, 'Tienda de Barrio');
  });

  test('304 (no modificado) → devuelve la cache sin re-parsear datos nuevos',
      () async {
    // Primer refresh siembra la cache.
    final seed = CatalogService(
      fetcher: ({String? etag}) async =>
          (data: _catalogJson(version: 'v1'), etag: '"abc"', notModified: false),
    );
    await seed.refresh();

    // Segundo: el servidor responde 304 (data null).
    final svc = CatalogService(
      fetcher: ({String? etag}) async =>
          (data: null, etag: '"abc"', notModified: true),
    );
    final c = await svc.refresh();
    expect(c, isNotNull);
    expect(c!.modules.length, 2, reason: 'conserva el catálogo cacheado');
  });

  test('offline (fetch lanza) → sirve la cache previa', () async {
    final seed = CatalogService(
      fetcher: ({String? etag}) async =>
          (data: _catalogJson(), etag: '"abc"', notModified: false),
    );
    await seed.refresh();

    final offline = CatalogService(
      fetcher: ({String? etag}) async => throw Exception('sin conexión'),
    );
    final c = await offline.refresh();
    expect(c, isNotNull, reason: 'offline usa el último catálogo conocido');
    expect(c!.modules.length, 2);
  });

  test('sin cache y sin red → null (el dashboard usará su bundle)', () async {
    final offline = CatalogService(
      fetcher: ({String? etag}) async => throw Exception('sin conexión'),
    );
    expect(await offline.refresh(), isNull);
  });
}
