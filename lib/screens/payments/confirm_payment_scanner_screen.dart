import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Reverse-QR scanner — staff side of the live-tab cash-at-waiter
/// flow. The customer's web page renders a QR with payload
/// `{"action":"confirm_payment","payment_id":"<uuid>"}`. We:
///
///   1. Open the camera and watch for QR detections.
///   2. Parse the payload defensively (any non-JSON or non-matching
///      action shows a helpful error and keeps scanning).
///   3. Show a confirmation dialog with the amount the backend
///      reports, so the staff can spot a mismatch BEFORE pocketing
///      the cash.
///   4. POST /orders/payments/:id/confirm to flip the abono to
///      APPROVED. The endpoint records the staff's user_id so
///      audits can trace cash receipts back to the person.
class ConfirmPaymentScannerScreen extends StatefulWidget {
  const ConfirmPaymentScannerScreen({super.key});

  @override
  State<ConfirmPaymentScannerScreen> createState() =>
      _ConfirmPaymentScannerScreenState();
}

class _ConfirmPaymentScannerScreenState
    extends State<ConfirmPaymentScannerScreen> {
  late final MobileScannerController _scanner;
  late final ApiService _api;
  bool _processing = false;
  String? _lastPaymentId;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
    );
    _api = ApiService(AuthService());
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _flashStatus(String msg) {
    if (!mounted) return;
    setState(() => _statusMessage = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _statusMessage == msg) {
        setState(() => _statusMessage = null);
      }
    });
  }

  /// Validates the QR payload without throwing. Returns the
  /// payment_id when it looks like a confirm-payment intent, null
  /// otherwise. Shape we accept:
  ///
  ///   { "action": "confirm_payment", "payment_id": "<uuid>" }
  ///
  /// Anything else (random product barcode, our own QR table-link,
  /// a Wi-Fi QR, a plain URL) is rejected so the cashier doesn't
  /// see "abono no encontrado" toasts when they accidentally point
  /// at the wrong thing.
  String? _extractPaymentId(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        if (decoded['action'] == 'confirm_payment') {
          final id = decoded['payment_id'];
          if (id is String && id.length >= 16) return id;
        }
      }
    } catch (_) {
      // Not JSON — could be a URL or plain text. Don't surface a
      // scary error; the scanner just keeps looking.
    }
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    final paymentId = _extractPaymentId(code);
    if (paymentId == null) {
      _flashStatus('Este código no es un cobro de cliente.');
      return;
    }
    if (paymentId == _lastPaymentId) return; // suppress double-fire
    _lastPaymentId = paymentId;

    HapticFeedback.mediumImpact();
    setState(() => _processing = true);
    await _scanner.stop();

    try {
      // We don't know the amount until the API replies — render the
      // confirmation dialog AFTER the call so the cashier sees the
      // exact figure the abono carries. A pre-call dialog would
      // either lie about the amount or require an extra GET.
      final res = await _api.confirmPartialPayment(paymentId);
      if (!mounted) return;
      final data =
          (res['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final method = (data['payment_method'] as String?) ?? 'Efectivo';
      final already = res['already'] == true;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _ConfirmedDialog(
          amount: amount,
          method: method,
          already: already,
        ),
      );

      if (!mounted) return;
      // Pop with the result so the dashboard / mesa screen can
      // reload state without inventing a separate broadcast.
      Navigator.of(context).pop<Map<String, dynamic>>({
        'payment_id': paymentId,
        'amount': amount,
        'already': already,
      });
    } catch (e) {
      if (!mounted) return;
      _flashStatus('No se pudo confirmar: $e');
      _lastPaymentId = null;
      setState(() => _processing = false);
      try {
        await _scanner.start();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Escanear pago de cliente',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
            onPressed: () => _scanner.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            key: const Key('confirm_payment_scanner'),
            controller: _scanner,
            onDetect: _onDetect,
          ),
          // Reticle
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.7), width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Confirmando…',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_statusMessage != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Apunta al QR que muestra el cliente.',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
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

class _ConfirmedDialog extends StatelessWidget {
  const _ConfirmedDialog({
    required this.amount,
    required this.method,
    required this.already,
  });

  final double amount;
  final String method;
  final bool already;

  String _fmtCOP(num value) {
    final v = value.round();
    final s = v.abs().toString();
    final buf = StringBuffer('\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final accent = already ? AppTheme.textSecondary : AppTheme.success;
    return AlertDialog(
      icon: Icon(
        already ? Icons.info_rounded : Icons.check_circle_rounded,
        color: accent,
        size: 48,
      ),
      title: Text(
        already ? 'Ya estaba cobrado' : '¡Pago registrado!',
        textAlign: TextAlign.center,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _fmtCOP(amount),
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: accent),
          ),
          const SizedBox(height: 4),
          Text(
            method,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
          if (already) ...[
            const SizedBox(height: 12),
            const Text(
              'Este código ya se había confirmado antes. No se duplicó el cobro.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Listo'),
        ),
      ],
    );
  }
}
