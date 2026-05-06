import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

/// Generates a PDF document for the full inventory report and returns bytes.
Future<Uint8List> buildInventoryReportPdfBytes({
  required List<Map<String, dynamic>> products,
  required String branchName,
  required int totalProducts,
}) async {
  final pdf = pw.Document();
  final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
  final currFmt = NumberFormat('#,###', 'es_CO');

  // Split products into pages of 25 rows each
  const rowsPerPage = 25;
  final pages = <List<Map<String, dynamic>>>[];
  for (var i = 0; i < products.length; i += rowsPerPage) {
    final end = (i + rowsPerPage > products.length) ? products.length : i + rowsPerPage;
    pages.add(products.sublist(i, end));
  }

  if (pages.isEmpty) pages.add([]);

  for (var pageIdx = 0; pageIdx < pages.length; pageIdx++) {
    final pageProducts = pages[pageIdx];
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Reporte de Inventario',
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('Sucursal: $branchName',
                        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('VendIA', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text(now, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                    pw.Text('$totalProducts productos',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 6),

            // Table
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellHeight: 22,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(3.5),
                1: const pw.FlexColumnWidth(1.8),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1),
                4: const pw.FlexColumnWidth(1),
                5: const pw.FlexColumnWidth(1.5),
              },
              headers: ['Producto', 'SKU / Pres.', 'Entr.', 'Sal.', 'Stock', 'Precio'],
              data: pageProducts.map((p) {
                final name = p['name'] as String? ?? '';
                final barcode = p['barcode'] as String? ?? '';
                final pres = p['presentation'] as String? ?? '';
                final content = p['content'] as String? ?? '';
                final sku = [
                  if (barcode.isNotEmpty) barcode,
                  if (pres.isNotEmpty) '$pres $content',
                ].join(' ');
                final totalIn = (p['total_in'] as num?)?.toInt() ?? 0;
                final totalOut = (p['total_out'] as num?)?.toInt() ?? 0;
                final stock = (p['stock'] as num?)?.toInt() ?? 0;
                final price = (p['price'] as num?)?.toDouble() ?? 0;
                return [
                  name,
                  sku,
                  '+$totalIn',
                  '-$totalOut',
                  '$stock',
                  '\$${currFmt.format(price.round())}',
                ];
              }).toList(),
            ),

            pw.Spacer(),

            // Footer
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Generado por VendIA',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                pw.Text('Pag. ${pageIdx + 1} de ${pages.length}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  return pdf.save();
}
