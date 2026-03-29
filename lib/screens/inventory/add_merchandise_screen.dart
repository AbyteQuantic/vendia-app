import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_theme.dart';
import 'ia_loading_screen.dart';
import 'create_product_screen.dart';
import '../pos/scan_screen.dart';

/// Agregar Mercancia — entry point for the inventory IA module.
/// Allows the user to photograph a supplier invoice for AI detection,
/// add products manually, or scan a barcode.
class AddMerchandiseScreen extends StatelessWidget {
  const AddMerchandiseScreen({super.key});

  Future<void> _openCamera(BuildContext context) async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (photo != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IaLoadingScreen(imagePath: photo.path),
        ),
      );
    }
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
      body: Semantics(
        label: 'Pantalla de agregar mercancia',
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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

                const SizedBox(height: 28),

                // Giant camera button
                Semantics(
                  button: true,
                  label: 'Leer factura del proveedor. Toque para abrir la camara',
                  child: GestureDetector(
                    onTap: () => _openCamera(context),
                    child: Container(
                      width: 315,
                      height: 340,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0x10667EEA),
                            Color(0x10764BA2),
                          ],
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
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: const Color(0x15667EEA),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 80,
                                color: Color(0xFF667EEA),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Leer Factura\ndel Proveedor',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF667EEA),
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Toque para abrir la camara',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

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

                const SizedBox(height: 16),

                // Tertiary: barcode scan
                SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ScanScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
                    label: const Text('Escanear codigo de barras'),
                  ),
                ),
              ],
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
