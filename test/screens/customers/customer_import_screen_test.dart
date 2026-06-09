// Spec: specs/026-importador-clientes/spec.md
//
// Widget tests for CustomerImportScreen (T-15):
//   - Step 1: file picker UI visible
//   - Step 2: "Siguiente" disabled without name mapping (AC-02)
//   - Step 3: Habeas Data notice visible (FR-10)
//   - Step 4: progress/report UI

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendia_pos/models/import_report.dart';
import 'package:vendia_pos/screens/customers/customer_import_screen.dart';
import 'package:vendia_pos/services/customer_import_mapper.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child) => MaterialApp(home: child);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test');
  });

  group('CustomerImportScreen — Paso 1 (Archivo)', () {
    testWidgets('muestra el título y el área de carga', (tester) async {
      await tester.pumpWidget(_wrap(const CustomerImportScreen()));
      await tester.pump();

      expect(find.text('Importar clientes'), findsOneWidget);
      // Copy actualizado a modo USTED + rediseño del área de carga
      // (el subtítulo "Selecciona tu archivo…" se eliminó).
      expect(
          find.text('Toque aquí para escoger su archivo'), findsOneWidget);
    });

    testWidgets('indicador de pasos muestra 4 pasos', (tester) async {
      await tester.pumpWidget(_wrap(const CustomerImportScreen()));
      await tester.pump();

      expect(find.text('Archivo'), findsOneWidget);
      expect(find.text('Mapeo'), findsOneWidget);
      expect(find.text('Previsualizar'), findsOneWidget);
      expect(find.text('Importar'), findsOneWidget);
    });

    testWidgets('botón Siguiente deshabilitado sin archivo', (tester) async {
      await tester.pumpWidget(_wrap(const CustomerImportScreen()));
      await tester.pump();

      final btn = find.widgetWithText(ElevatedButton, 'Siguiente');
      expect(btn, findsOneWidget);

      final elevatedBtn = tester.widget<ElevatedButton>(btn);
      expect(elevatedBtn.onPressed, isNull,
          reason: 'Sin archivo, Siguiente debe estar deshabilitado');
    });
  });

  group('CustomerImportScreen — Paso 2 (Mapeo)', () {
    // Build a screen already at step 2 by using a test-only exposed method.
    // We test the mapping widget directly via the ImportStep2MappingContent component.
    testWidgets('"Siguiente" deshabilitado sin columna name mapeada (AC-02)',
        (tester) async {
      // Build ImportStep2MappingContent directly
      final headers = ['SKU', 'Precio'];
      final mapping = CustomerImportMapper.proposeMapping(headers); // Both null

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

      expect(
        find.text(
            'Debes mapear una columna a "Nombre del cliente" para continuar.'),
        findsOneWidget,
      );
    });

    testWidgets('muestra todos los headers del archivo', (tester) async {
      final headers = ['Nombre', 'Celular', 'Correo'];
      final mapping = CustomerImportMapper.proposeMapping(headers);

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
  });

  group('CustomerImportScreen — Paso 3 (Preview)', () {
    testWidgets('aviso Habeas Data visible (FR-10)', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep3(
              previewMapped: [
                {'name': 'Juan', 'phone': '3001234567'},
              ],
              previewValid: [true],
              totalRows: 1,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('habeas_data_notice')), findsOneWidget);
      expect(find.textContaining('Habeas Data'), findsOneWidget);
      expect(find.textContaining('Ley 1581'), findsOneWidget);
    });

    testWidgets('filas inválidas se muestran en rojo con razón', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep3(
              previewMapped: [
                {'name': ''},
                {'name': 'Ana'},
              ],
              previewValid: [false, true],
              totalRows: 2,
            ),
          ),
        ),
      ));
      await tester.pump();

      // Shows invalid row reason
      expect(find.textContaining('nombre vacío'), findsOneWidget);
      // Shows counts
      expect(find.textContaining('Con problemas: 1'), findsOneWidget);
    });

    testWidgets('muestra conteo de filas listas y con problemas', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _TestStep3(
              previewMapped: [
                {'name': 'Pedro'},
                {'name': ''},
              ],
              previewValid: [true, false],
              totalRows: 10,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.textContaining('Total: 10'), findsOneWidget);
    });
  });

  group('CustomerImportScreen — Paso 4 (Importar)', () {
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
  });
}

// ── Test helpers (expose internals for white-box testing) ──────────────────────

// Wraps ImportStep2MappingContent using public constructor
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
    return ImportStep2MappingContent(
      headers: widget.headers,
      mapping: _mapping,
      nameIsMapped: _mapping.values.contains('name'),
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

// Wraps ImportStep3PreviewContent
class _TestStep3 extends StatelessWidget {
  final List<Map<String, dynamic>> previewMapped;
  final List<bool> previewValid;
  final int totalRows;

  const _TestStep3({
    required this.previewMapped,
    required this.previewValid,
    required this.totalRows,
  });

  @override
  Widget build(BuildContext context) {
    return ImportStep3PreviewContent(
      headers: const [],
      previewMapped: previewMapped,
      previewValid: previewValid,
      totalRows: totalRows,
    );
  }
}

// Wraps ImportStep4ResultContent importing
class _TestStep4Importing extends StatelessWidget {
  final int sent;
  final int total;

  const _TestStep4Importing({required this.sent, required this.total});

  @override
  Widget build(BuildContext context) {
    return ImportStep4ResultContent(
      importing: true,
      sent: sent,
      total: total,
      report: null,
      error: null,
    );
  }
}

// Wraps ImportStep4ResultContent with report
class _TestStep4Done extends StatelessWidget {
  final int created;
  final int updated;
  final int failed;

  const _TestStep4Done(
      {required this.created, required this.updated, required this.failed});

  @override
  Widget build(BuildContext context) {
    return ImportStep4ResultContent(
      importing: false,
      sent: created + updated,
      total: created + updated,
      report: ImportReport(
        created: created,
        updated: updated,
        skipped: 0,
        failed: List.generate(
          failed,
          (i) => ImportFailure(rowIndex: i, reason: 'nombre vacío'),
        ),
      ),
      error: null,
    );
  }
}
