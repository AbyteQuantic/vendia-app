import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/product.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _scannerCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _processing = false;
  String? _lastScannedCode;

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!;
    if (code == _lastScannedCode) return;

    setState(() {
      _processing = true;
      _lastScannedCode = code;
    });

    HapticFeedback.lightImpact();
    await _lookupProduct(code);
  }

  Future<void> _lookupProduct(String barcode) async {
    try {
      final api = ApiService(AuthService());
      final response = await api.fetchProducts();
      final allProducts = (response['data'] as List?) ?? [];
      final results = allProducts
          .cast<Map<String, dynamic>>()
          .where((p) => p['barcode'] == barcode)
          .toList();

      if (!mounted) return;

      if (results.isNotEmpty) {
        final product = Product.fromJson(results.first);
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(product);
      } else {
        _showNotFoundDialog(barcode);
      }
    } on AppError catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(e.message, style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
      setState(() => _processing = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
    }
  }

  void _showNotFoundDialog(String barcode) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Producto no encontrado',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'No se encontró un producto con el código $barcode.\n\n¿Desea crearlo?',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _processing = false;
                _lastScannedCode = null;
              });
            },
            child: const Text('Seguir escaneando',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
              // TODO: navigate to create product screen with barcode pre-filled
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(120, 56)),
            child: const Text('Crear producto',
                style: TextStyle(fontSize: 18, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        label: 'Pantalla de escáner de código de barras',
        child: Stack(
          children: [
            MobileScanner(
              controller: _scannerCtrl,
              onDetect: _onDetect,
            ),

            // Overlay with guide frame
            _ScanOverlay(isProcessing: _processing),

            // Back button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: Semantics(
                button: true,
                label: 'Volver',
                child: IconButton(
                  icon: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: 28),
                  ),
                  tooltip: 'Volver',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            // Flash toggle
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: Semantics(
                button: true,
                label: 'Encender linterna',
                child: IconButton(
                  icon: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.flashlight_on_rounded,
                        color: Colors.white, size: 28),
                  ),
                  tooltip: 'Linterna',
                  onPressed: () => _scannerCtrl.toggleTorch(),
                ),
              ),
            ),

            // Bottom instruction
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 40,
              left: 24,
              right: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _processing
                      ? 'Buscando producto...'
                      : 'Apunte la cámara al código de barras del producto',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  final bool isProcessing;
  const _ScanOverlay({required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.75;
        final top = (constraints.maxHeight - scanAreaSize) / 2;
        final left = (constraints.maxWidth - scanAreaSize) / 2;

        return Stack(
          children: [
            // Dark overlay with cutout
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.5),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: top,
                    left: left,
                    child: Container(
                      width: scanAreaSize,
                      height: scanAreaSize,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Corner markers
            Positioned(
              top: top - 2,
              left: left - 2,
              child: _Corner(isProcessing: isProcessing),
            ),
            Positioned(
              top: top - 2,
              right: left - 2,
              child: Transform.flip(
                  flipX: true, child: _Corner(isProcessing: isProcessing)),
            ),
            Positioned(
              bottom: constraints.maxHeight - top - scanAreaSize - 2,
              left: left - 2,
              child: Transform.flip(
                  flipY: true, child: _Corner(isProcessing: isProcessing)),
            ),
            Positioned(
              bottom: constraints.maxHeight - top - scanAreaSize - 2,
              right: left - 2,
              child: Transform.flip(
                  flipX: true,
                  flipY: true,
                  child: _Corner(isProcessing: isProcessing)),
            ),

            if (isProcessing)
              Positioned(
                top: top + scanAreaSize / 2 - 24,
                left: left + scanAreaSize / 2 - 24,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Corner extends StatelessWidget {
  final bool isProcessing;
  const _Corner({required this.isProcessing});

  @override
  Widget build(BuildContext context) {
    final color = isProcessing ? AppTheme.success : Colors.white;
    return SizedBox(
      width: 40,
      height: 40,
      child: CustomPaint(
        painter: _CornerPainter(color: color),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}
