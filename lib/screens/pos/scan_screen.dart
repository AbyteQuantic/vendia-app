import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../database/database_service.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../inventory/create_product_screen.dart';

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
      // 1. Search local Isar first (instant, works offline)
      final localMatch = await DatabaseService.instance
          .getProductByBarcode(barcode);
      if (localMatch != null) {
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(barcode);
        return;
      }

      // 2. Dedicated barcode lookup — searches the ENTIRE tenant
      //    catalog without branch filters so employees in any
      //    branch can find any product.
      final api = ApiService(AuthService());
      final match = await api.lookupProductByBarcode(barcode);

      if (!mounted) return;

      if (match != null) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(barcode);
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
          'Código no reconocido',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No hay producto con el código $barcode.',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              'Si ya creó el producto sin el código (lo digitó manual), puede '
              'asociarlo ahora — la próxima vez el escáner lo reconoce.',
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actionsOverflowButtonSpacing: 8,
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
          OutlinedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showAssociateSheet(barcode);
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size(120, 56)),
            child: const Text('Asociar a uno existente',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => CreateProductScreen(initialSku: barcode),
                ),
              );
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(120, 56)),
            child: const Text('Crear nuevo',
                style: TextStyle(fontSize: 16, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Search-and-pick sheet that lets the cashier link the just-scanned
  /// barcode to a product the dueño already created (manually, without
  /// scanning). On confirmation we PATCH the product so future scans hit
  /// the fast path. Pops the ScanScreen with `barcode` so the caller
  /// adds the now-linked product to the cart on the next tick.
  Future<void> _showAssociateSheet(String barcode) async {
    final api = ApiService(AuthService());
    List<Map<String, dynamic>> all = [];
    try {
      final resp = await api.fetchProducts(perPage: 500);
      all = ((resp['data'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .where((p) =>
              ((p['barcode'] ?? '') as String).isEmpty) // only un-linked
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudieron cargar los productos: $e',
            style: const TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.error,
      ));
      setState(() {
        _processing = false;
        _lastScannedCode = null;
      });
      return;
    }

    if (!mounted) return;
    if (all.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Todos sus productos ya tienen un código asignado.',
          style: TextStyle(fontSize: 16),
        ),
      ));
      setState(() {
        _processing = false;
        _lastScannedCode = null;
      });
      return;
    }

    String query = '';
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final filtered = query.isEmpty
              ? all
              : all
                  .where((p) => ((p['name'] ?? '') as String)
                      .toLowerCase()
                      .contains(query.toLowerCase()))
                  .toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (_, scroll) => Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('Asociar código a un producto',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Código: $barcode',
                            style: const TextStyle(
                                fontSize: 16,
                                color: AppTheme.textSecondary)),
                        const SizedBox(height: 12),
                        TextField(
                          autofocus: true,
                          style: const TextStyle(fontSize: 18),
                          decoration: const InputDecoration(
                            hintText: 'Buscar por nombre...',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                          onChanged: (v) => setSt(() => query = v),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('Sin resultados',
                                style: TextStyle(
                                    fontSize: 18,
                                    color: AppTheme.textSecondary)),
                          )
                        : ListView.separated(
                            controller: scroll,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = filtered[i];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                title: Text(
                                  (p['name'] ?? '') as String,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  'Stock: ${p['stock'] ?? 0} · Precio: ${p['price'] ?? 0}',
                                  style: const TextStyle(fontSize: 15),
                                ),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppTheme.primary),
                                onTap: () => Navigator.of(ctx).pop(p),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (picked == null) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _lastScannedCode = null;
      });
      return;
    }

    try {
      await api.updateProduct(picked['id'] as String, {'barcode': barcode});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo asociar el código: $e',
            style: const TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.error,
      ));
      setState(() {
        _processing = false;
        _lastScannedCode = null;
      });
      return;
    }

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '✓ ${picked['name']} ahora reconoce el código $barcode',
        style: const TextStyle(fontSize: 16),
      ),
      backgroundColor: AppTheme.success,
    ));
    Navigator.of(context).pop(barcode);
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
            // Dark semitransparent overlay with clear cutout
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _OverlayPainter(
                scanRect: Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize),
                borderRadius: 24,
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

/// Paints a semitransparent overlay with a clear rounded-rect cutout.
class _OverlayPainter extends CustomPainter {
  final Rect scanRect;
  final double borderRadius;

  _OverlayPainter({required this.scanRect, required this.borderRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = Colors.black54;
    final clearPaint = Paint()..blendMode = BlendMode.clear;

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, Radius.circular(borderRadius)),
      clearPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.scanRect != scanRect;
}
