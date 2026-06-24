// Spec: specs/026-importador-clientes/spec.md
//
// Wizard de importación de clientes en 4 pasos (Stepper).
// Cross-platform: usa XFile.readAsBytes() — sin dart:io ni path_provider.
// Soporta .xlsx (parse via archive+xml), .csv (separadores , y ;, UTF-8 y latin-1).
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
import '../../services/customer_import_mapper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const int _kMaxFileSizeBytes = 5 * 1024 * 1024; // 5 MB
const int _kMaxRows = 5000;
const int _kPreviewRows = 20;

// ── Screen ────────────────────────────────────────────────────────────────────

class CustomerImportScreen extends StatefulWidget {
  const CustomerImportScreen({super.key});

  @override
  State<CustomerImportScreen> createState() => _CustomerImportScreenState();
}

class _CustomerImportScreenState extends State<CustomerImportScreen> {
  int _step = 0;

  // Step 1 — file
  String? _fileName;
  String? _fileError;
  List<String> _headers = [];
  List<List<dynamic>> _rawRows = [];

  // Step 2 — mapping
  // mapping[headerIndex] = targetColumn ('name','phone','email','notes') or null
  Map<int, String?> _mapping = {};

  // Step 3 — preview
  // Computed from _rawRows + _mapping
  List<Map<String, dynamic>> _previewMapped = [];
  List<bool> _previewValid = [];

  // Step 4 — result
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
      _mapping = CustomerImportMapper.proposeMapping(headers);
    });
  }

  // ── XLSX parser using archive + xml ─────────────────────────────────────

  (List<String>, List<List<dynamic>>) _parseXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Read shared strings
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

    // Read first sheet
    final sheetFile = archive.findFile('xl/worksheets/sheet1.xml')
        ?? archive.findFile('xl/worksheets/Sheet1.xml');
    if (sheetFile == null) {
      throw const FormatException('No se encontró la primera hoja en el archivo XLSX.');
    }

    final sheetXml = xml_lib.XmlDocument.parse(
        utf8.decode(sheetFile.content as List<int>, allowMalformed: true));

    // Build row → col → value table
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
          // Shared string
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
      final cells = List<dynamic>.generate(
          maxCol + 1, (i) => cols[i] ?? '');
      if (headers == null) {
        headers = cells.map((c) => c.toString()).toList();
      } else {
        dataRows.add(cells);
      }
    }

    return (headers ?? [], dataRows);
  }

  int _colLetterToIndex(String ref) {
    // e.g. "A1" → 0, "B1" → 1, "AA3" → 26
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
    // Try UTF-8 first, fall back to latin-1
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    // Detect separator: if more ';' than ',' in first line → use ';'
    final firstLine = content.split('\n').first;
    final sep = firstLine.split(';').length > firstLine.split(',').length
        ? ';'
        : ',';

    // Normalize ';' to ',' for the decoder
    final normalized = sep == ';' ? content.replaceAll(';', ',') : content;

    const decoder = csv_pkg.CsvDecoder(
      fieldDelimiter: ',',
      skipEmptyLines: true,
    );
    final rows = decoder.convert(normalized);

    // Remove fully-empty rows
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

  void _computePreview() {
    final mapped = <Map<String, dynamic>>[];
    final valid = <bool>[];
    final rows = _rawRows.take(_kPreviewRows);
    for (final row in rows) {
      final m = CustomerImportMapper.applyMapping(row, _mapping);
      mapped.add(m);
      valid.add(CustomerImportMapper.validateRow(m).ok);
    }
    _previewMapped = mapped;
    _previewValid = valid;
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _startImport() async {
    final allMapped = _rawRows
        .map((r) => CustomerImportMapper.applyMapping(r, _mapping))
        .toList();
    final validRows =
        allMapped.where((r) => CustomerImportMapper.validateRow(r).ok).toList();

    setState(() {
      _importing = true;
      _importSent = 0;
      _importTotal = validRows.length;
      _report = null;
      _importError = null;
    });

    try {
      final report = await _api.importCustomers(
        validRows,
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
          'Importar clientes',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
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
        return _nameIsMapped;
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
        return ImportStep2MappingContent(
          headers: _headers,
          mapping: _mapping,
          nameIsMapped: _nameIsMapped,
          onMappingChanged: (idx, target) {
            setState(() {
              // Unclaim current target if it was assigned elsewhere
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
        return ImportStep3PreviewContent(
          headers: _headers,
          previewMapped: _previewMapped,
          previewValid: _previewValid,
          totalRows: _rawRows.length,
        );
      case 3:
        return ImportStep4ResultContent(
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
          'Suba su lista de clientes',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Si ya lleva sus clientes en una hoja de cálculo o cuaderno '
          'digital, puede subir el archivo y VendIA los cargará '
          'automáticamente.',
          style: TextStyle(
            fontSize: 16,
            color: AppTheme.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        const _FieldsGuideCard(),
        const SizedBox(height: 20),
        const _FileSpecsCard(),
        const SizedBox(height: 24),
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
                  fileName ?? 'Toque aquí para escoger su archivo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        fileName != null ? FontWeight.bold : FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (fileName == null) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'Excel (.xlsx) o CSV',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                if (fileName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$rowCount filas encontradas',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                    ),
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
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppTheme.error,
                    ),
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

const _kTargetLabels = {
  'name': 'Nombre del cliente',
  'phone': 'Teléfono',
  'email': 'Correo electrónico',
  'notes': 'Notas',
};

class ImportStep2MappingContent extends StatelessWidget {
  final List<String> headers;
  final Map<int, String?> mapping;
  final bool nameIsMapped;
  final void Function(int idx, String? target) onMappingChanged;

  const ImportStep2MappingContent({
    super.key,
    required this.headers,
    required this.mapping,
    required this.nameIsMapped,
    required this.onMappingChanged,
  });

  @override
  Widget build(BuildContext context) {
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
          'Solo el Nombre es obligatorio.',
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
        if (!nameIsMapped) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppTheme.error, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Debes mapear una columna a "Nombre del cliente" para continuar.',
                    style: TextStyle(fontSize: 16, color: AppTheme.error),
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
              style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
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
                borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— No importar —',
                    style: TextStyle(
                        fontSize: 15, color: AppTheme.textSecondary)),
              ),
              ..._kTargetLabels.entries.map((e) => DropdownMenuItem<String?>(
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

class ImportStep3PreviewContent extends StatelessWidget {
  final List<String> headers;
  final List<Map<String, dynamic>> previewMapped;
  final List<bool> previewValid;
  final int totalRows;

  const ImportStep3PreviewContent({
    super.key,
    required this.headers,
    required this.previewMapped,
    required this.previewValid,
    required this.totalRows,
  });

  @override
  Widget build(BuildContext context) {
    final invalidCount = previewValid.where((v) => !v).length;
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
        const SizedBox(height: 16),

        // Habeas Data notice (FR-10)
        Container(
          key: const Key('habeas_data_notice'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFD700)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Color(0xFF856404), size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Al importar, declaras que estos clientes te dieron sus '
                  'datos voluntariamente. Habeas Data (Ley 1581) requiere '
                  'consentimiento separado para campañas — marketing queda '
                  'desactivado por defecto.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF664D03),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (previewMapped.isEmpty)
          const Text(
            'Sin filas para previsualizar.',
            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
          )
        else
          ...List.generate(previewMapped.length, (i) {
            final row = previewMapped[i];
            final valid = i < previewValid.length ? previewValid[i] : true;
            return _PreviewRow(row: row, valid: valid, index: i);
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

class _PreviewRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool valid;
  final int index;

  const _PreviewRow({
    required this.row,
    required this.valid,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final bg = valid
        ? (index.isEven ? Colors.white : AppTheme.surfaceGrey)
        : AppTheme.error.withValues(alpha: 0.08);
    final borderColor =
        valid ? Colors.transparent : AppTheme.error.withValues(alpha: 0.4);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            valid ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: valid ? AppTheme.success : AppTheme.error,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['name']?.toString().isNotEmpty == true
                      ? row['name'].toString()
                      : '(sin nombre)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color:
                        valid ? AppTheme.textPrimary : AppTheme.error,
                  ),
                ),
                if ((row['phone'] as String? ?? '').isNotEmpty)
                  Text(
                    row['phone'].toString(),
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary),
                  ),
                if (!valid) ...[
                  const SizedBox(height: 2),
                  Text(
                    CustomerImportMapper.validateRow(row).reason ??
                        'Fila inválida',
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

class ImportStep4ResultContent extends StatelessWidget {
  final bool importing;
  final int sent;
  final int total;
  final ImportReport? report;
  final String? error;

  const ImportStep4ResultContent({
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
            'Importando… $sent de $total clientes',
            style: const TextStyle(fontSize: 18, color: AppTheme.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppTheme.surfaceGrey,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
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
            'Los clientes enviados antes del error quedan guardados. '
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
              style: const TextStyle(
                  fontSize: 18, color: AppTheme.textPrimary)),
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

// ── Guía visual de campos esperados (UI/UX Pro Max F040) ─────────────────────
//
// Tarjeta que muestra ANTES del dropzone qué columnas se reconocen.
// Diferencia obligatorios (ícono ⭐ + chip "Obligatorio") de opcionales,
// para que el tendero entienda qué necesita preparar antes de elegir el
// archivo. Aplica `form-labels` + `required-indicators` + `empty-states`
// + `color-only` (icono + texto, no solo color) del skill ui-ux-pro-max.

class _FieldsGuideCard extends StatelessWidget {
  const _FieldsGuideCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.18), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_outlined,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Qué necesita tener su archivo',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _FieldRow(
            icon: Icons.person_rounded,
            iconColor: Color(0xFF1A2FA0),
            title: 'Nombre del cliente',
            description: 'Cómo lo apunta en su cuaderno (ej. "María", '
                '"Don José", "Supermercado La Esquina").',
            required: true,
          ),
          const SizedBox(height: 12),
          const _FieldRow(
            icon: Icons.phone_rounded,
            iconColor: Color(0xFF059669),
            title: 'Teléfono',
            description: 'Sirve para WhatsApp, cuentas de fiado y para que '
                'no se repitan clientes con el mismo nombre.',
          ),
          const SizedBox(height: 12),
          const _FieldRow(
            icon: Icons.alternate_email_rounded,
            iconColor: Color(0xFFD97706),
            title: 'Correo',
            description: 'Si manda cotizaciones o facturas por correo.',
          ),
          const SizedBox(height: 12),
          const _FieldRow(
            icon: Icons.sticky_note_2_outlined,
            iconColor: Color(0xFF7C3AED),
            title: 'Notas',
            description: 'Observaciones libres: gustos, descuentos especiales, '
                'fechas a recordar.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    color: Color(0xFF075985), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No importa el orden de las columnas, ni que el nombre '
                    'sea exacto: en el paso siguiente le mostramos cuál cree '
                    'que es cuál y usted confirma.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF075985),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de un campo en la guía. El "Obligatorio" se comunica con
/// icono ⭐ + chip de texto (no solo color — guía #37 del skill).
class _FieldRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool required;

  const _FieldRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (required) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded,
                              color: AppTheme.error, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Obligatorio',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.error,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tarjeta compacta con los límites técnicos del archivo.
class _FileSpecsCard extends StatelessWidget {
  const _FileSpecsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded,
              color: AppTheme.textSecondary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Excel (.xlsx) o CSV · hasta 5 MB · hasta 5.000 filas · '
              'primera fila con nombres de columna',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
