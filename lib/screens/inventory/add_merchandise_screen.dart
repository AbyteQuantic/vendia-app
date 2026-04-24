import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import 'ia_loading_screen.dart';
import 'create_product_screen.dart';
import 'manage_inventory_screen.dart';
import 'voice_inventory_screen.dart';
import '../pos/scan_screen.dart';

/// Agregar Mercancia — entry point for the inventory IA module.
/// Allows the user to photograph a supplier invoice for AI detection,
/// add products manually, or scan a barcode.
class AddMerchandiseScreen extends StatelessWidget {
  const AddMerchandiseScreen({super.key});

  /// Shows the image-source chooser (camera vs. gallery) before
  /// launching the picker. Split from [_processInvoice] so the
  /// main button stays a single tap-target while still giving
  /// tenderos with pre-taken invoices a path in — they asked for
  /// this explicitly.
  Future<void> _showImageSourceBottomSheet(BuildContext context) async {
    HapticFeedback.lightImpact();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Text(
                  '¿De dónde viene la factura?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              ListTile(
                key: const Key('invoice_source_camera'),
                leading: const Icon(Icons.camera_alt_rounded,
                    size: 32, color: Color(0xFF2563EB)),
                title: const Text(
                  'Tomar foto con la cámara',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Úselo si tiene la factura en papel frente a usted',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processInvoice(context, ImageSource.camera);
                },
              ),
              ListTile(
                key: const Key('invoice_source_gallery'),
                leading: const Icon(Icons.photo_library_rounded,
                    size: 32, color: Color(0xFF059669)),
                title: const Text(
                  'Subir foto desde la galería',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Úselo si ya le tomó foto antes o se la enviaron por WhatsApp',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _processInvoice(context, ImageSource.gallery);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  /// Launches the actual [ImagePicker] with the chosen [source],
  /// validates the payload, and routes to the AI loading screen.
  /// Unified so camera and gallery share identical validation /
  /// navigation code paths — no drift possible.
  Future<void> _processInvoice(
      BuildContext context, ImageSource source) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (photo == null || !context.mounted) return;

    // Validate file size before sending to AI
    final fileSize = await photo.length();
    const maxBytes = 5 * 1024 * 1024; // 5 MB

    if (fileSize > maxBytes) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.photo_size_select_large_rounded,
                  color: Colors.white, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'La foto es muy pesada. Tome la foto con buena luz y un poco más de lejos.',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IaLoadingScreen(imagePath: photo.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Agregar Mercancia',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Description
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Tome una foto a la factura del proveedor y la IA '
                  'detectara los productos automaticamente.',
                  style: TextStyle(
                    fontSize: 18,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 24),

              // Giant camera button (reduced height for small screens)
              GestureDetector(
                key: const Key('btn_read_invoice'),
                onTap: () => _showImageSourceBottomSheet(context),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0x10667EEA), Color(0x10764BA2)],
                    ),
                  ),
                  child: CustomPaint(
                    painter: _DashedBorderPainter(
                      color: const Color(0x40667EEA),
                      strokeWidth: 2,
                      radius: 28,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0x15667EEA),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              size: 56, color: Color(0xFF667EEA)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Leer Factura del Proveedor',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667EEA),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Toque para tomar o subir la foto',
                          style: TextStyle(
                              fontSize: 16, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Voice-to-Catalog (Phase 4 killer feature). Sits above
              // the manual entry so tenderos see it as the "modern"
              // alternative to camera OCR; press-and-hold UX lives
              // inside VoiceInventoryScreen.
              SizedBox(
                height: 64,
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('btn_voice_inventory'),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const VoiceInventoryScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.mic_rounded, size: 26),
                  label: const Text('🎤 Dictar inventario por voz',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),

              const SizedBox(height: 12),

              // Secondary: manual product
              SizedBox(
                height: 64,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateProductScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_rounded, size: 24),
                  label: const Text('Agregar producto manualmente'),
                ),
              ),

              const SizedBox(height: 12),

              // Tertiary: barcode scan
              SizedBox(
                height: 64,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    final barcode = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const ScanScreen()),
                    );
                    // If scanner returns a barcode (product found), go to create with SKU
                    if (barcode != null && barcode.isNotEmpty && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CreateProductScreen(initialSku: barcode),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                  label: const Text('Escanear código de barras'),
                ),
              ),
            ],
          ),
        ),
      ),
      // ── Fixed bottom button: Administrar inventario ──
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 64,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ManageInventoryScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.inventory_rounded, size: 24),
              label: const Text('Administrar inventario'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a dashed rounded-rectangle border.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    const dashLength = 10.0;
    const gapLength = 6.0;

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashLength).clamp(0.0, metric.length);
        final segment = metric.extractPath(distance, end);
        canvas.drawPath(segment, paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
