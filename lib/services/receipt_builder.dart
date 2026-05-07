import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;

/// Snapshot of merchant identity for the receipt header.
class ReceiptTenantInfo {
  const ReceiptTenantInfo({
    required this.businessName,
    this.nit,
    this.address,
    this.phone,
    this.logoBytes, // PNG/JPEG raw bytes; null if no logo configured
  });
  final String businessName;
  final String? nit;
  final String? address;
  final String? phone;
  final Uint8List? logoBytes;
}

/// One sale line as it should appear on the printed ticket.
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });
  final String name;
  final int quantity;
  final double unitPrice;
  double get subtotal => quantity * unitPrice;
}

/// Build the byte stream for a single sale receipt. Pure: no platform calls,
/// no logging, no I/O. Safe to unit-test.
class ReceiptBuilder {
  ReceiptBuilder({
    required this.tenant,
    required this.lines,
    required this.total,
    required this.paymentMethod,
    this.paperSize = PaperSize.mm58,
    this.openDrawer = true,
    this.cutPaper = true,
  });

  final ReceiptTenantInfo tenant;
  final List<ReceiptLine> lines;
  final double total;
  final String paymentMethod;
  final PaperSize paperSize;
  final bool openDrawer;
  final bool cutPaper;

  /// Returns the raw ESC/POS byte stream ready to send over the transport.
  /// Throws nothing — degraded gracefully when the logo can't be decoded
  /// (skip header image, keep text only).
  Future<List<int>> build() async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(paperSize, profile);
    final bytes = <int>[];

    bytes.addAll(gen.reset());

    // Logo (top, centered). If decoding fails, we silently skip — the rest of
    // the receipt is more important than the brand mark.
    if (tenant.logoBytes != null && tenant.logoBytes!.isNotEmpty) {
      try {
        final decoded = img.decodeImage(tenant.logoBytes!);
        if (decoded != null) {
          // Resize to a sensible width for thermal printers (max 300px).
          final maxWidth = paperSize == PaperSize.mm80 ? 300 : 200;
          final resized = decoded.width > maxWidth
              ? img.copyResize(decoded, width: maxWidth)
              : decoded;
          // Convert to grayscale + threshold dithering for 1-bit print.
          final gray = img.grayscale(resized);
          // Generator.image handles the final dither + raster cmd.
          bytes.addAll(gen.image(gray, align: PosAlign.center));
          bytes.addAll(gen.feed(1));
        }
      } catch (_) {
        // Logo failed — proceed with text-only header.
      }
    }

    // Business name (large, centered).
    bytes.addAll(gen.text(
      tenant.businessName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ));

    // NIT + address + phone (small, centered).
    if ((tenant.nit ?? '').isNotEmpty) {
      bytes.addAll(gen.text('NIT ${tenant.nit}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    if ((tenant.address ?? '').isNotEmpty) {
      bytes.addAll(gen.text(tenant.address!,
          styles: const PosStyles(align: PosAlign.center)));
    }
    if ((tenant.phone ?? '').isNotEmpty) {
      bytes.addAll(gen.text('Tel: ${tenant.phone}',
          styles: const PosStyles(align: PosAlign.center)));
    }

    bytes.addAll(gen.hr());

    // Date + time of sale, left-aligned for the cashier's records.
    final now = DateTime.now();
    final stamp =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}'
        '  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    bytes.addAll(gen.text(stamp,
        styles: const PosStyles(align: PosAlign.left)));
    bytes.addAll(gen.feed(1));

    // Items table — three columns: qty, name (truncated), subtotal.
    for (final line in lines) {
      bytes.addAll(gen.row([
        PosColumn(
          text: '${line.quantity}',
          width: 2,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: line.name,
          width: 7,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: _formatMoney(line.subtotal),
          width: 3,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }

    bytes.addAll(gen.hr());

    // Total (bold, larger).
    bytes.addAll(gen.row([
      PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
      PosColumn(
        text: _formatMoney(total),
        width: 6,
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    ]));

    bytes.addAll(gen.text('Pago: ${paymentMethod.toUpperCase()}',
        styles: const PosStyles(align: PosAlign.left, bold: true)));

    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.text('¡Gracias por su compra!',
        styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(gen.text('Vuelva pronto',
        styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(gen.feed(2));

    if (openDrawer) {
      // Drawer kick — pin 2, 25ms on, 250ms off. Standard for the RJ11 cash
      // drawers wired through the printer's RJ jack.
      bytes.addAll([27, 112, 0, 25, 250]);
    }

    if (cutPaper) {
      bytes.addAll(gen.cut());
    }

    return bytes;
  }

  static String _formatMoney(double v) {
    final cents = v.round();
    if (cents == 0) return '\$0';
    final s = cents.abs().toString();
    final buf = StringBuffer(cents < 0 ? '-\$' : '\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }
}
