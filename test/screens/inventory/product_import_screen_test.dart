// Spec: specs/027-importador-inventario/spec.md
//
// Widget tests para ProductImportScreen (T-14):
//   - Paso 1: UI de selección de archivo visible
//   - Paso 2: "Siguiente" deshabilitado sin mapeo de name y price (AC-02)
//   - Paso 3: preview con precio parseado visible
//   - Paso 4: progreso/reporte UI
// Espejo arquitectónico de customer_import_screen_test.dart (F026).

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/import_report.dart';
import 'package:vendia_pos/screens/inventory/product_import_screen.dart';
import 'package:vendia_pos/services/product_import_mapper.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: child);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test');
  });

  group('ProductImportScreen — Paso 1 (Archivo)', () {
    testWidgets('muestra el título y el área de carga', (tester) async {
      await tester.pumpWidget(_wrap(const ProductImportScreen()));
      await tester.pump();

      expect(find.text('Importar inventario'), findsOneWidget);
      expect(find.text('Selecciona tu archivo de inventario'), findsOneWidget);
      expect(find.text('Toca aquí para seleccionar un archivo'), findsOneWidget);
    });

    testWidgets('indicador de pasos muestra 4 pasos', (tester) async {
      await tester.pumpWidget(_wrap(const ProductImportScreen()));
      await tester.pump();

      expect(find.text('Archivo'), findsOneWidget);
      expect(find.text('Mapeo'), findsOneWidget);
      expect(find.text('Previsualizar'), findsOneWidget);
      expect(find.text('Importar'), findsOneWidget);
    });

    testWidgets('botón Siguiente deshabilitado sin archivo', (tester) async {
      await tester.pumpWidget(_wrap(const ProductImportScreen()));
      await tester.pump();

      final btn = find.widgetWithText(ElevatedButton, 'Siguiente');
      expect(btn, findsOneWidget);

      final elevatedBtn = tester.widget<ElevatedButton>(btn);
      expect(elevatedBtn.onPressed, isNull,
          reason: 'Sin archivo, Siguiente debe estar deshabilitado');
    });
  });

  group('ProductImportScreen — Paso 2 (Mapeo)', () {
    testWidgets(
        '"Siguiente" deshabilitado sin name y price mapeados (AC-02)',
        (tester) async {
      final headers = ['Proveedor', 'Referencia interna'];
      final mapping = ProductImportMapper.proposeMapping(headers);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: _TestStep2(
                    headers: headers,
                    mapping: Map.from(mapping),
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('Nombre del producto'), findsWidgets);
      expect(find.textContaining('Precio de venta'), findsWidgets);
    });

    testWidgets('muestra todos los headers del archivo', (tester) async {
      final headers = ['Producto', 'Precio Venta', 'Código de Barras'];
      final mapping = ProductImportMapper.proposeMapping(headers);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep2(
              headers: headers,
              mapping: Map.from(mapping),
            ),
          ),
        ),
      ));
      await tester.pump();

      for (final h in headers) {
        expect(find.text(h), findsOneWidget);
      }
    });

    testWidgets('muestra aviso cuando faltan name y price', (tester) async {
      final headers = ['SKU', 'Referencia'];
      final mapping = ProductImportMapper.proposeMapping(headers);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep2(
              headers: headers,
              mapping: Map.from(mapping),
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('product_mapping_warning')), findsOneWidget);
    });
  });

  group('ProductImportScreen — Paso 3 (Preview)', () {
    testWidgets('muestra fila válida con nombre y precio parseado',
        (tester) async {
      final previewRows = [
        ProductPreviewRow(
          mapped: {'name': 'Coca Cola 350ml', 'price': '2500'},
          valid: true,
          validationReason: null,
          parsedPrice: 2500.0,
          rawPrice: '2500',
          stockDecimalWarning: false,
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep3(previewRows: previewRows, totalRows: 1),
          ),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('Coca Cola 350ml'), findsOneWidget);
      expect(find.textContaining('2.500'), findsOneWidget);
    });

    testWidgets('muestra filas inválidas con razón en rojo', (tester) async {
      final previewRows = [
        ProductPreviewRow(
          mapped: {'name': '', 'price': '0'},
          valid: false,
          validationReason: 'nombre vacío',
          parsedPrice: null,
          rawPrice: '0',
          stockDecimalWarning: false,
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep3(previewRows: previewRows, totalRows: 1),
          ),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('nombre vacío'), findsOneWidget);
      expect(find.textContaining('Con problemas: 1'), findsOneWidget);
    });

    testWidgets('muestra warning de stock decimal', (tester) async {
      final previewRows = [
        ProductPreviewRow(
          mapped: {'name': 'Pan', 'price': '500', 'stock': '1.5'},
          valid: true,
          validationReason: null,
          parsedPrice: 500.0,
          rawPrice: '500',
          stockDecimalWarning: true,
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep3(previewRows: previewRows, totalRows: 1),
          ),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('redondeado'), findsOneWidget);
    });

    testWidgets('muestra precio original → precio parseado (transparencia)',
        (tester) async {
      final previewRows = [
        ProductPreviewRow(
          mapped: {'name': 'Leche', 'price': r'$ 1.500'},
          valid: true,
          validationReason: null,
          parsedPrice: 1500.0,
          rawPrice: r'$ 1.500',
          stockDecimalWarning: false,
        ),
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep3(previewRows: previewRows, totalRows: 1),
          ),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('1.500'), findsWidgets);
    });
  });

  group('ProductImportScreen — Paso 4 (Importar)', () {
    testWidgets('muestra barra de progreso durante importación', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: _TestStep4Importing(sent: 50, total: 100),
        ),
      ));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('50 de 100'), findsOneWidget);
    });

    testWidgets('muestra reporte al finalizar', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep4Done(created: 30, updated: 5, failed: 2),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('¡Importación completa!'), findsOneWidget);
      expect(find.text('Creados'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('Actualizados'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('muestra mensaje de error cuando falla la importación',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep4Error(
                error: 'Error de conexión: sin respuesta del servidor'),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('Error al importar'), findsOneWidget);
      expect(find.textContaining('Error de conexión'), findsOneWidget);
    });
  });
}

// ── Test helpers ──────────────────────────────────────────────────────────────

class _TestStep2 extends StatefulWidget {
  final List<String> headers;
  final Map<int, String?> mapping;

  const _TestStep2({required this.headers, required this.mapping});

  @override
  State<_TestStep2> createState() => _TestStep2State();
}

class _TestStep2State extends State<_TestStep2> {
  late Map<int, String?> _mapping;

  @override
  void initState() {
    super.initState();
    _mapping = Map.from(widget.mapping);
  }

  @override
  Widget build(BuildContext context) {
    return ProductImportStep2MappingContent(
      headers: widget.headers,
      mapping: _mapping,
      nameIsMapped: _mapping.values.contains('name'),
      priceIsMapped: _mapping.values.contains('price'),
      onMappingChanged: (idx, target) {
        setState(() {
          if (target != null) {
            for (final key in _mapping.keys) {
              if (_mapping[key] == target) _mapping[key] = null;
            }
          }
          _mapping[idx] = target;
        });
      },
    );
  }
}

class _TestStep3 extends StatelessWidget {
  final List<ProductPreviewRow> previewRows;
  final int totalRows;

  const _TestStep3({required this.previewRows, required this.totalRows});

  @override
  Widget build(BuildContext context) {
    return ProductImportStep3PreviewContent(
      previewRows: previewRows,
      totalRows: totalRows,
    );
  }
}

class _TestStep4Importing extends StatelessWidget {
  final int sent;
  final int total;

  const _TestStep4Importing({required this.sent, required this.total});

  @override
  Widget build(BuildContext context) {
    return ProductImportStep4ResultContent(
      importing: true,
      sent: sent,
      total: total,
      report: null,
      error: null,
    );
  }
}

class _TestStep4Done extends StatelessWidget {
  final int created;
  final int updated;
  final int failed;

  const _TestStep4Done(
      {required this.created, required this.updated, required this.failed});

  @override
  Widget build(BuildContext context) {
    return ProductImportStep4ResultContent(
      importing: false,
      sent: created + updated,
      total: created + updated,
      report: ImportReport(
        created: created,
        updated: updated,
        skipped: 0,
        failed: List.generate(
          failed,
          (i) => ImportFailure(rowIndex: i, reason: 'precio inválido'),
        ),
      ),
      error: null,
    );
  }
}

class _TestStep4Error extends StatelessWidget {
  final String error;

  const _TestStep4Error({required this.error});

  @override
  Widget build(BuildContext context) {
    return ProductImportStep4ResultContent(
      importing: false,
      sent: 0,
      total: 0,
      report: null,
      error: error,
    );
  }
}
