// Spec: specs/042-modulo-eventos/spec.md
//
// Escáner de check-in/out (F042). El organizador escanea el QR de la
// escarapela del asistente para registrar entrada o salida (AC-08, AC-11).
// Reusa mobile_scanner. El backend es idempotente: reescanear el mismo QR
// devuelve "ya registrado".

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class EventCheckinScanScreen extends StatefulWidget {
  final String eventId;

  /// 'in' (entrada) u 'out' (salida).
  final String scanType;
  final ApiService? apiOverride;

  const EventCheckinScanScreen({
    super.key,
    required this.eventId,
    this.scanType = ScanType.checkIn,
    this.apiOverride,
  });

  @override
  State<EventCheckinScanScreen> createState() => _EventCheckinScanScreenState();
}

class _EventCheckinScanScreenState extends State<EventCheckinScanScreen> {
  late final ApiService _api;
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
  );

  String? _lastCode;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code =
        capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (code == null || code.isEmpty || code == _lastCode) return;
    _lastCode = code;
    setState(() => _busy = true);
    try {
      final already =
          await _api.checkinEvent(widget.eventId, code, widget.scanType);
      if (!mounted) return;
      _toast(
        already ? 'Ese código ya estaba registrado' : '¡Registrado!',
        already ? Colors.orange : Colors.green,
      );
    } catch (_) {
      if (!mounted) return;
      _toast('Código no válido para este evento', Colors.red);
    } finally {
      // Pequeña pausa para evitar relecturas del mismo encuadre.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        setState(() => _busy = false);
        _lastCode = null;
      }
    }
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.scanType == ScanType.checkOut
        ? 'Salida (check-out)'
        : 'Entrada (check-in)';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          if (_busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Apunte la cámara al código QR de la escarapela del asistente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tipos de escaneo (espejo del backend: 'in' / 'out').
class ScanType {
  static const checkIn = 'in';
  static const checkOut = 'out';
}
