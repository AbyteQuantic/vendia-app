// Spec: specs/027-importador-inventario/spec.md
//
// Wizard de importación de inventario en 4 pasos (Stepper).
// Espejo arquitectónico de customer_import_screen.dart (F026).
// Cross-platform: usa XFile.readAsBytes() — sin dart:io ni path_provider.
// Soporta .xlsx (archive+xml) y .csv (separadores , y ;, UTF-8 y latin-1).
// Archivos .xls (legacy) se rechazan con mensaje explicativo.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart' as csv_pkg;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart' as xml_lib;

import '../../models/import_report.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/product_import_mapper.dart';
import '../../theme/app_theme.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const int _kMaxFileSizeBytes = 5 * 1024 * 1024; // 5 MB
const int _kMaxRows = 5000;
const int _kPreviewRows = 20;

/// Fila de previsualización con precio parseado y flags de warning.
class ProductPreviewRow {
  final Map<String, dynamic> mapped;
  final bool valid;
  final String? validationReason;
  final double? parsedPrice;
  final String rawPrice;
  final bool stockDecimalWarning;

  const ProductPreviewRow({
    required this.mapped,
    required this.valid,
    required this.validationReason,
    required this.parsedPrice,
    required this.rawPrice,
    required this.stockDecimalWarning,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ProductImportScreen extends StatefulWidget {
  const ProductImportScreen({super.key});

  @override
  State<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends State<ProductImportScreen> {
  int _step = 0;

  // Paso 1 — archivo
  String? _fileName;
  String? _fileError;
  List<String> _headers = [];
  List<List<dynamic>> _rawRows = [];

  // Paso 2 — mapeo
  // mapping[headerIndex] = targetColumn o null
  Map<int, String?> _mapping = {};

  // Paso 3 — preview
  List<ProductPreviewRow> _previewRows = [];

  // Paso 4 — resultado
  bool _importing = false;
  int _importSent = 0;
  int _importTotal = 0;
  ImportReport? _report;
  String? _importError;

  late final ApiService _api;

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
  }

  // ── File parsing ─────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() {
      _fileError = null;
      _fileName = null;
      _headers = [];
      _rawRows = [];
    });

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final name = file.name.toLowerCase();
    final bytes = file.bytes;

    if (bytes == null) {
      setState(() => _fileError = 'No se pudo leer el archivo.');
      return;
    }

    if (name.endsWith('.xls') && !name.endsWith('.xlsx')) {
      setState(() => _fileError =
          'El formato .xls antiguo no está soportado. '
          'Abre el archivo en Excel y guárdalo como .xlsx, luego intenta de nuevo.');
      return;
    }

    if (bytes.length > _kMaxFileSizeBytes) {
      setState(() => _fileError =
          'El archivo pesa más de 5 MB. Por favor divide el archivo en partes más pequeñas.');
      return;
    }

    List<String> headers;
    List<List<dynamic>> rows;

    try {
      if (name.endsWith('.xlsx')) {
        final parsed = _parseXlsx(bytes);
        headers = parsed.$1;
        rows = parsed.$2;
      } else {
        final parsed = _parseCsv(bytes);
        headers = parsed.$1;
        rows = parsed.$2;
      }
    } catch (e) {
      setState(() => _fileError = 'No se pudo leer el archivo: $e');
      return;
    }

    if (rows.length > _kMaxRows) {
      setState(() => _fileError =
          'El archivo tiene más de $_kMaxRows filas. Por favor divide el archivo en partes de máximo $_kMaxRows filas.');
      return;
    }

    setState(() {
      _fileName = file.name;
      _headers = headers;
      _rawRows = rows;
      _mapping = ProductImportMapper.proposeMapping(headers);
    });
  }

  // ── XLSX parser (archive + xml) — espejo de customer_import_screen ────────

  (List<String>, List<List<dynamic>>) _parseXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final sharedStrings = <String>[];
    final ssFile = archive.findFile('xl/sharedStrings.xml');
    if (ssFile != null) {
      final ssXml = xml_lib.XmlDocument.parse(
          utf8.decode(ssFile.content as List<int>, allowMalformed: true));
      for (final si in ssXml.findAllElements('si')) {
        final t = si.findAllElements('t').map((e) => e.innerText).join();
        sharedStrings.add(t);
      }
    }

    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')
        ?? archive.findFile('xl/worksheets/Sheet1.xml');
    if (sheetFile == null) {
      throw const FormatException('No se encontró la primera hoja en el archivo XLSX.');
    }

    final sheetXml = xml_lib.XmlDocument.parse(
        utf8.decode(sheetFile.content as List<int>, allowMalformed: true));

    final rowMap = <int, Map<int, String>>{};

    for (final row in sheetXml.findAllElements('row')) {
      final rowNum = int.tryParse(row.getAttribute('r') ?? '') ?? 0;
      rowMap[rowNum] = {};
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r') ?? '';
        final colIdx = _colLetterToIndex(ref);
        final type = c.getAttribute('t') ?? '';
        final vEl = c.findElements('v').firstOrNull;
        if (vEl == null) {
          rowMap[rowNum]![colIdx] = '';
          continue;
        }
        String value;
        if (type == 's') {
          final idx = int.tryParse(vEl.innerText) ?? 0;
          value = idx < sharedStrings.length ? sharedStrings[idx] : '';
        } else if (type == 'inlineStr') {
          value = c.findAllElements('t').map((e) => e.innerText).join();
        } else {
          value = vEl.innerText;
        }
        rowMap[rowNum]![colIdx] = value;
      }
    }

    if (rowMap.isEmpty) return ([], []);

    final sortedRows = rowMap.keys.toList()..sort();
    final maxCol = rowMap.values
        .expand((m) => m.keys)
        .fold(0, (a, b) => a > b ? a : b);

    List<String>? headers;
    final dataRows = <List<dynamic>>[];

    for (final rowNum in sortedRows) {
      final cols = rowMap[rowNum]!;
      final cells =
          List<dynamic>.generate(maxCol + 1, (i) => cols[i] ?? '');
      if (headers == null) {
        headers = cells.map((c) => c.toString()).toList();
      } else {
        dataRows.add(cells);
      }
    }

    return (headers ?? [], dataRows);
  }

  int _colLetterToIndex(String ref) {
    var col = 0;
    for (final ch in ref.runes) {
      final c = String.fromCharCode(ch);
      if (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) {
        col = col * 26 + (ch - 'A'.codeUnitAt(0) + 1);
      } else {
        break;
      }
    }
    return col - 1;
  }

  // ── CSV parser ────────────────────────────────────────────────────────────

  (List<String>, List<List<dynamic>>) _parseCsv(Uint8List bytes) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    final firstLine = content.split('\n').first;
    final sep = firstLine.split(';').length > firstLine.split(',').length
        ? ';'
        : ',';

    final normalized = sep == ';' ? content.replaceAll(';', ',') : content;

    const decoder = csv_pkg.CsvDecoder(
      fieldDelimiter: ',',
      skipEmptyLines: true,
    );
    final rows = decoder.convert(normalized);

    final nonEmpty = rows
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .toList();

    if (nonEmpty.isEmpty) return ([], []);
    final headers = nonEmpty.first.map((c) => c.toString()).toList();
    final data = nonEmpty.skip(1).toList();
    return (headers, data);
  }

  // ── Mapping helpers ────────────────────────────────────────────────────────

  bool get _nameIsMapped => _mapping.values.contains('name');
  bool get _priceIsMapped => _mapping.values.contains('price');
  bool get _bothRequiredMapped => _nameIsMapped && _priceIsMapped;

  void _computePreview() {
    final rows = <ProductPreviewRow>[];
    for (final raw in _rawRows.take(_kPreviewRows)) {
      final mapped = ProductImportMapper.applyMapping(raw, _mapping);
      final validation = ProductImportMapper.validateRow(mapped);
      final rawPrice = mapped['price']?.toString() ?? '';
      final parsedPrice = ProductImportMapper.normalizePriceCOP(rawPrice);
      final stockWarning = ProductImportMapper.stockHasDecimalWarning(mapped);

      rows.add(ProductPreviewRow(
        mapped: mapped,
        valid: validation.ok,
        validationReason: validation.reason,
        parsedPrice: parsedPrice,
        rawPrice: rawPrice,
        stockDecimalWarning: stockWarning,
      ));
    }
    _previewRows = rows;
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _startImport() async {
    final allMapped = _rawRows
        .map((r) => ProductImportMapper.applyMapping(r, _mapping))
        .toList();
    final validRows = allMapped
        .where((r) => ProductImportMapper.validateRow(r).ok)
        .toList();

    // Normalize price to double before sending (backend also normalizes,
    // but client-side normalization avoids ambiguity in the wire format).
    final wireRows = validRows.map((row) {
      final result = Map<String, dynamic>.from(row);
      final rawPrice = result['price']?.toString() ?? '';
      final parsedPrice = ProductImportMapper.normalizePriceCOP(rawPrice);
      if (parsedPrice != null) result['price'] = parsedPrice;

      // Normalize stock to int
      final rawStock = result['stock']?.toString() ?? '';
      if (rawStock.isNotEmpty) {
        final stockVal = double.tryParse(rawStock);
        if (stockVal != null && stockVal >= 0) {
          result['stock'] = stockVal.round();
        }
      }
      return result;
    }).toList();

    setState(() {
      _importing = true;
      _importSent = 0;
      _importTotal = wireRows.length;
      _report = null;
      _importError = null;
    });

    try {
      final report = await _api.importProducts(
        wireRows,
        onProgress: (sent, total) {
          if (mounted) setState(() => _importSent = sent);
        },
      );
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) setState(() => _importError = e.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _goNext() {
    if (_step == 1) _computePreview();
    if (_step == 2) _startImport();
    if (_step < 3) setState(() => _step++);
  }

  void _goBack() {
    if (_step > 0) setState(() => _step--);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Importar inventario',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepIndicator(currentStep: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _buildStepContent(),
              ),
            ),
            _BottomNav(
              step: _step,
              canNext: _canAdvance(),
              onNext: _goNext,
              onBack: _goBack,
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvance() {
    switch (_step) {
      case 0:
        return _headers.isNotEmpty && _fileError == null;
      case 1:
        return _bothRequiredMapped;
      case 2:
        return !_importing;
      case 3:
        return false;
    }
    return false;
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _Step1FilePickerContent(
          fileName: _fileName,
          fileError: _fileError,
          rowCount: _rawRows.length,
          onPick: _pickFile,
        );
      case 1:
        return ProductImportStep2MappingContent(
          headers: _headers,
          mapping: _mapping,
          nameIsMapped: _nameIsMapped,
          priceIsMapped: _priceIsMapped,
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
      case 2:
        return ProductImportStep3PreviewContent(
          previewRows: _previewRows,
          totalRows: _rawRows.length,
        );
      case 3:
        return ProductImportStep4ResultContent(
          importing: _importing,
          sent: _importSent,
          total: _importTotal,
          report: _report,
          error: _importError,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Step indicator ─────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    const labels = ['Archivo', 'Mapeo', 'Previsualizar', 'Importar'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(
              child: Container(
                height: 2,
                color: i ~/ 2 < currentStep
                    ? AppTheme.primary
                    : AppTheme.surfaceGrey,
              ),
            );
          }
          final step = i ~/ 2;
          final done = step < currentStep;
          final active = step == currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || active ? AppTheme.primary : AppTheme.surfaceGrey,
                ),
                child: Center(
                  child: done
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : Text(
                          '${step + 1}',
                          style: TextStyle(
                            color: active ? Colors.white : AppTheme.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[step],
                style: TextStyle(
                  fontSize: 11,
                  color: active ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Step 1 — File picker ──────────────────────────────────────────────────────

class _Step1FilePickerContent extends StatelessWidget {
  final String? fileName;
  final String? fileError;
  final int rowCount;
  final VoidCallback onPick;

  const _Step1FilePickerContent({
    required this.fileName,
    required this.fileError,
    required this.rowCount,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selecciona tu archivo de inventario',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Formatos aceptados: .xlsx, .csv\n'
          'Tamaño máximo: 5 MB · Máximo 5.000 filas\n'
          'La primera fila debe tener los nombres de columna.',
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 40),
            decoration: BoxDecoration(
              border: Border.all(
                color: fileError != null
                    ? AppTheme.error
                    : AppTheme.primary.withValues(alpha: 0.4),
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
              borderRadius: BorderRadius.circular(16),
              color: AppTheme.surfaceGrey,
            ),
            child: Column(
              children: [
                Icon(
                  fileName != null
                      ? Icons.insert_drive_file_rounded
                      : Icons.upload_file_rounded,
                  size: 56,
                  color: AppTheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  fileName ?? 'Toca aquí para seleccionar un archivo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        fileName != null ? FontWeight.bold : FontWeight.normal,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (fileName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$rowCount filas encontradas',
                    style: const TextStyle(
                        fontSize: 15, color: AppTheme.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (fileError != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_rounded, color: AppTheme.error, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    fileError!,
                    style: const TextStyle(fontSize: 16, color: AppTheme.error),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (fileName != null) ...[
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Cambiar archivo', style: TextStyle(fontSize: 16)),
          ),
        ],
      ],
    );
  }
}

// ── Step 2 — Column mapping ───────────────────────────────────────────────────

const _kProductTargetLabels = {
  'name': 'Nombre del producto',
  'price': 'Precio de venta',
  'barcode': 'Código de barras',
  'purchase_price': 'Precio de compra',
  'stock': 'Stock',
  'min_stock': 'Stock mínimo',
  'category': 'Categoría',
  'emoji': 'Emoji',
  'unit': 'Unidad',
  'presentation': 'Presentación',
  'content': 'Contenido',
  'expiry_date': 'Fecha de vencimiento',
};

class ProductImportStep2MappingContent extends StatelessWidget {
  final List<String> headers;
  final Map<int, String?> mapping;
  final bool nameIsMapped;
  final bool priceIsMapped;
  final void Function(int idx, String? target) onMappingChanged;

  const ProductImportStep2MappingContent({
    super.key,
    required this.headers,
    required this.mapping,
    required this.nameIsMapped,
    required this.priceIsMapped,
    required this.onMappingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final showWarning = !nameIsMapped || !priceIsMapped;
    final missingFields = <String>[];
    if (!nameIsMapped) missingFields.add('"Nombre del producto"');
    if (!priceIsMapped) missingFields.add('"Precio de venta"');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mapea las columnas de tu archivo',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Dinos qué columna es cada campo. '
          'Nombre del producto y Precio de venta son obligatorios.',
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        ...List.generate(headers.length, (i) {
          final header = headers[i];
          final current = mapping[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _MappingRow(
              headerName: header,
              selectedTarget: current,
              onChanged: (val) => onMappingChanged(i, val),
            ),
          );
        }),
        if (showWarning) ...[
          const SizedBox(height: 8),
          Container(
            key: const Key('product_mapping_warning'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppTheme.error, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Debes mapear una columna a ${missingFields.join(' y ')} para continuar.',
                    style: const TextStyle(fontSize: 16, color: AppTheme.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MappingRow extends StatelessWidget {
  final String headerName;
  final String? selectedTarget;
  final void Function(String?) onChanged;

  const _MappingRow({
    required this.headerName,
    required this.selectedTarget,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              headerName,
              style:
                  const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.arrow_forward_rounded,
              color: AppTheme.textSecondary, size: 20),
        ),
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: selectedTarget,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.surfaceGrey),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— No importar —',
                    style: TextStyle(
                        fontSize: 15, color: AppTheme.textSecondary)),
              ),
              ..._kProductTargetLabels.entries.map((e) =>
                  DropdownMenuItem<String?>(
                    value: e.key,
                    child: Text(e.value,
                        style: const TextStyle(
                            fontSize: 15, color: AppTheme.textPrimary)),
                  )),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ── Step 3 — Preview ──────────────────────────────────────────────────────────

class ProductImportStep3PreviewContent extends StatelessWidget {
  final List<ProductPreviewRow> previewRows;
  final int totalRows;

  const ProductImportStep3PreviewContent({
    super.key,
    required this.previewRows,
    required this.totalRows,
  });

  @override
  Widget build(BuildContext context) {
    final invalidCount = previewRows.where((r) => !r.valid).length;
    final okCount = totalRows - invalidCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Previsualización',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Total: $totalRows filas · Listas: $okCount · Con problemas: $invalidCount (se omitirán)',
          style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 20),

        if (previewRows.isEmpty)
          const Text(
            'Sin filas para previsualizar.',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          )
        else
          ...List.generate(previewRows.length, (i) {
            final row = previewRows[i];
            return _ProductPreviewRowWidget(row: row, index: i);
          }),

        if (totalRows > _kPreviewRows) ...[
          const SizedBox(height: 12),
          Text(
            '… y ${totalRows - _kPreviewRows} filas más (se importarán todas las válidas).',
            style: const TextStyle(
                fontSize: 15,
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }
}

/// Widget que muestra una fila de preview con precio original → precio parseado
/// (transparencia ante ambigüedad de formato COP, AC-03).
class _ProductPreviewRowWidget extends StatelessWidget {
  final ProductPreviewRow row;
  final int index;

  const _ProductPreviewRowWidget({required this.row, required this.index});

  /// Formatea un double como precio COP sin símbolo de moneda.
  /// Ej: 1500.0 → "1.500"
  String _formatCOP(double val) {
    // Simple thousands separator for integers
    final intPart = val.truncate();
    final decPart = val - intPart;
    final intStr = intPart.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    if (decPart == 0) return intStr;
    final decStr = (decPart * 100).round().toString().padLeft(2, '0');
    return '$intStr,$decStr';
  }

  @override
  Widget build(BuildContext context) {
    final bg = row.valid
        ? (index.isEven ? Colors.white : AppTheme.surfaceGrey)
        : AppTheme.error.withValues(alpha: 0.08);
    final borderColor = row.valid
        ? Colors.transparent
        : AppTheme.error.withValues(alpha: 0.4);

    final name = row.mapped['name']?.toString() ?? '';
    final parsedPrice = row.parsedPrice;
    final rawPrice = row.rawPrice;
    final showPriceTransparency =
        parsedPrice != null && rawPrice != _formatCOP(parsedPrice);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              row.valid ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: row.valid ? AppTheme.success : AppTheme.error,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : '(sin nombre)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: row.valid ? AppTheme.textPrimary : AppTheme.error,
                  ),
                ),
                if (parsedPrice != null) ...[
                  const SizedBox(height: 2),
                  // Show parsed price; if original was ambiguous format, show both
                  if (showPriceTransparency)
                    Text(
                      '$rawPrice → \$${_formatCOP(parsedPrice)}',
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                    )
                  else
                    Text(
                      '\$${_formatCOP(parsedPrice)}',
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                    ),
                ],
                if (row.stockDecimalWarning) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 14, color: AppTheme.warning),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Stock decimal redondeado a ${(double.tryParse(row.mapped['stock']?.toString() ?? '0') ?? 0).round()}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.warning),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!row.valid && row.validationReason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    row.validationReason!,
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.error,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 4 — Import progress & result ─────────────────────────────────────────

class ProductImportStep4ResultContent extends StatelessWidget {
  final bool importing;
  final int sent;
  final int total;
  final ImportReport? report;
  final String? error;

  const ProductImportStep4ResultContent({
    super.key,
    required this.importing,
    required this.sent,
    required this.total,
    required this.report,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (importing) {
      final progress = total == 0 ? 0.0 : sent / total;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          const CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 24),
          Text(
            'Importando… $sent de $total productos',
            style: const TextStyle(fontSize: 18, color: AppTheme.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppTheme.surfaceGrey,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).round()}%',
            style: const TextStyle(
                fontSize: 16, color: AppTheme.textSecondary),
          ),
        ],
      );
    }

    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ResultHeader(
            icon: Icons.error_rounded,
            color: AppTheme.error,
            title: 'Error al importar',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(error!,
                style:
                    const TextStyle(fontSize: 15, color: AppTheme.error)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Los productos enviados antes del error quedan guardados. '
            'Puedes volver e intentar de nuevo.',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
        ],
      );
    }

    if (report != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _ResultHeader(
            icon: Icons.check_circle_rounded,
            color: AppTheme.success,
            title: '¡Importación completa!',
          ),
          const SizedBox(height: 24),
          _ReportCard(
              label: 'Creados',
              value: report!.created,
              color: AppTheme.success),
          _ReportCard(
              label: 'Actualizados',
              value: report!.updated,
              color: AppTheme.primary),
          _ReportCard(
              label: 'Omitidos',
              value: report!.skipped,
              color: AppTheme.textSecondary),
          if (report!.failed.isNotEmpty) ...[
            _ReportCard(
                label: 'Fallidos',
                value: report!.failed.length,
                color: AppTheme.error),
            const SizedBox(height: 16),
            const Text(
              'Detalle de filas con fallo:',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            ...report!.failed.map(
              (f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.cancel_rounded,
                        color: AppTheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(f.toString(),
                          style: const TextStyle(
                              fontSize: 15, color: AppTheme.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _ResultHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;

  const _ResultHeader({
    required this.icon,
    required this.color,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ReportCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 18, color: AppTheme.textPrimary)),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom navigation ─────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int step;
  final bool canNext;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _BottomNav({
    required this.step,
    required this.canNext,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    if (step == 3) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check_rounded, size: 24),
            label: const Text('Cerrar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        children: [
          if (step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  side: const BorderSide(color: AppTheme.primary, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Atrás',
                    style: TextStyle(
                        fontSize: 18,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          if (step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: canNext ? onNext : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.surfaceGrey,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                step == 2 ? 'Importar' : 'Siguiente',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
