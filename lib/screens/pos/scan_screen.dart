import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../database/database_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/html5_qrcode_scanner.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // Formatos típicos de productos retail Colombia.
  // ⚠️ EN WEB es obligatorio especificarlos — el motor wasm de
  // `mobile_scanner` no detecta nada si la lista queda vacía.
  //
  // Lista deliberadamente corta y enfocada: muchos formatos confunden
  // al ZXing WASM en web, que parsea cada frame contra cada formato
  // y a veces salta al "menos probable" en condiciones de baja luz /
  // baja resolución, sin emitir el match al callback. Con la lista
  // mínima retail-CO el detector se enfoca y emite consistentemente.
  static const _retailFormats = <BarcodeFormat>[
    BarcodeFormat.ean13, // tiendas / minimercados — el más común
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.code128, // ferreterías / distribuidoras
    BarcodeFormat.qrCode, // SKUs propios en QR
  ];

  // `back` apunta al producto en móvil. En web el navegador lo traduce
  // a la cámara disponible.
  //
  // `DetectionSpeed.normal` (en lugar de `noDuplicates`): en mobile_scanner
  // ^5.2.3 el modo `noDuplicates` tiene un bug conocido en el motor wasm
  // web — bajo ciertas condiciones nunca emite el primer detect porque
  // su filtro interno asume duplicado erróneamente. El dedup nuestro
  // (variable `_lastScannedCode` en `_onDetect`) ya cubre el caso, así
  // que delegar el dedup al package es redundante y arriesgado en web.
  final MobileScannerController _scannerCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: _retailFormats,
    returnImage: false,
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
    // Estrategia: el escáner solo retorna el barcode (encontrado o
    // no). El POS decide qué hacer — si no existe, muestra el diálogo
    // de "Crear producto" allá, NO acá. Razón: en web el wrapper de
    // html5-qrcode (z-index 999999, en document.body) tapa cualquier
    // dialog/sheet que Flutter intente abrir mientras el scanner está
    // activo. El POS no tiene ese problema porque el wrapper ya está
    // removido cuando volvemos a la pantalla anterior.
    try {
      // 1. Search local Isar first (instant, works offline) — solo
      //    para reportar match al POS más rápido. Si no existe local
      //    igual popeamos con el barcode, POS reintenta vía API.
      final localMatch = await DatabaseService.instance
          .getProductByBarcode(barcode);
      if (!mounted) return;
      if (localMatch != null) {
        HapticFeedback.mediumImpact();
      }
      Navigator.of(context).pop(barcode);
    } catch (_) {
      if (!mounted) return;
      // Fallback defensivo: aún así devolvemos el barcode al POS,
      // que tiene su propia lógica de búsqueda + manejo de errores.
      Navigator.of(context).pop(barcode);
    }
  }

  // Las funciones _showNotFoundDialog y _showAssociateSheet vivían
  // acá pero el wrapper HTML del scanner web (z-index 999999) las
  // tapaba — el tendero no veía nada. Movidas al POS
  // (pos_screen.dart → _onBarcodeScanned) donde sí se renderean
  // correctamente porque el wrapper ya está removido cuando volvemos
  // a la pantalla anterior.

  /// Wrapper sobre `_onDetect` para el path web (html5-qrcode) que
  /// solo recibe un string del código, no un `BarcodeCapture`.
  Future<void> _onDetectedFromWeb(String code) async {
    if (_processing) return;
    if (code == _lastScannedCode) return;
    setState(() {
      _processing = true;
      _lastScannedCode = code;
    });
    HapticFeedback.lightImpact();
    await _lookupProduct(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        label: 'Pantalla de escáner de código de barras',
        child: Stack(
          children: [
            // En web usamos html5-qrcode (JS, motor probado en iOS
            // Safari). En móvil usamos mobile_scanner v7 nativo.
            // El path móvil mantiene exactamente el comportamiento
            // que ya funciona en producción.
            if (kIsWeb)
              Html5QrcodeScannerWidget(
                onDetected: _onDetectedFromWeb,
              )
            else
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

            // Bottom instruction (subida para no chocar con Cancelar)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 120,
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

            // Botón CANCELAR grande — el tendero 50+ necesita un
            // control evidente para salir del scanner sin tener
            // que buscar la flecha pequeña arriba.
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 20,
              right: 20,
              child: Semantics(
                button: true,
                label: 'Cancelar escaneo y volver a la venta',
                child: SizedBox(
                  height: 64,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.white, width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
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
