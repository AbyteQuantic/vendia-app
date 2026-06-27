// Spec: specs/083-mesas-catalogo-qr/spec.md
//
// Mesero escanea el QR de una mesa (tienda.vendia.store/<slug>?mesa=<id>) para
// abrir la cuenta de ESA mesa y tomar el pedido (ayuda a clientes que no quieren
// o no saben pedir por su celular). Devuelve por Navigator.pop el id de la mesa
// extraído del QR. Móvil (MobileScanner); el flujo del POS hace el resto.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_theme.dart';

/// Extrae el `mesa` de una URL de QR de mesa. Acepta el id por query
/// (`?mesa=<id>`) y devuelve null si el código no es un QR de mesa válido.
String? parseMesaIdFromQr(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  final fromQuery = uri.queryParameters['mesa'];
  if (fromQuery != null && fromQuery.trim().isNotEmpty) {
    return fromQuery.trim();
  }
  return null;
}

class TableQrScanScreen extends StatefulWidget {
  const TableQrScanScreen({super.key});

  @override
  State<TableQrScanScreen> createState() => _TableQrScanScreenState();
}

class _TableQrScanScreenState extends State<TableQrScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    returnImage: false,
  );
  bool _handled = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final mesaId = parseMesaIdFromQr(raw);
      if (mesaId != null) {
        _handled = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(mesaId);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear QR de la mesa'),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _ctrl, onDetect: _onDetect),
          // Marco guía + instrucción para el mesero.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Text(
              'Apunte al QR pegado en la mesa para abrir su cuenta.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 6)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
