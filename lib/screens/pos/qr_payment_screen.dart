import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';

class QrPaymentScreen extends StatefulWidget {
  final double total;
  final String formattedTotal;

  const QrPaymentScreen({
    super.key,
    required this.total,
    required this.formattedTotal,
  });

  @override
  State<QrPaymentScreen> createState() => _QrPaymentScreenState();
}

class _QrPaymentScreenState extends State<QrPaymentScreen> {
  String _nequiPhone = '';
  String _daviplataPhone = '';

  @override
  void initState() {
    super.initState();
    _loadPaymentConfig();
  }

  Future<void> _loadPaymentConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nequiPhone = prefs.getString('vendia_nequi_phone') ?? '';
      _daviplataPhone = prefs.getString('vendia_daviplata_phone') ?? '';
    });
  }

  String get _qrData {
    final phone = _nequiPhone.isNotEmpty ? _nequiPhone : _daviplataPhone;
    return 'Pagar ${formatCOP(widget.total)} a Nequi $phone';
  }

  void _confirmPayment() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado', style: const TextStyle(fontSize: 18)),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasConfig = _nequiPhone.isNotEmpty || _daviplataPhone.isNotEmpty;

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
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
        title: const Text(
          'Pago por Transferencia',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Pantalla de pago con QR',
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Total
                Text(
                  'Total:',
                  style: const TextStyle(
                      fontSize: 20, color: AppTheme.textSecondary),
                ),
                Text(
                  widget.formattedTotal,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 24),

                // QR Code
                if (hasConfig)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: QrImageView(
                      data: _qrData,
                      version: QrVersions.auto,
                      size: 250,
                      backgroundColor: Colors.white,
                    ),
                  ),
                if (!hasConfig)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.warning_rounded,
                            size: 40, color: Color(0xFFF59E0B)),
                        SizedBox(height: 12),
                        Text(
                          'Configure sus números de Nequi/Daviplata en Administrar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 18, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 24),

                // Phone numbers
                if (_nequiPhone.isNotEmpty)
                  _PhoneRow(
                    label: 'Nequi',
                    phone: _nequiPhone,
                    color: const Color(0xFF311B92),
                    onCopy: () => _copyToClipboard(_nequiPhone, 'Nequi'),
                  ),
                if (_daviplataPhone.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _PhoneRow(
                    label: 'Daviplata',
                    phone: _daviplataPhone,
                    color: AppTheme.error,
                    onCopy: () =>
                        _copyToClipboard(_daviplataPhone, 'Daviplata'),
                  ),
                ],

                const SizedBox(height: 32),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: _confirmPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded,
                        size: 28, color: Colors.white),
                    label: const Text(
                      'YA RECIBÍ EL PAGO',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Cancel button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: TextButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop(false);
                    },
                    icon: const Icon(Icons.close_rounded,
                        size: 22, color: AppTheme.textSecondary),
                    label: const Text(
                      'CANCELAR',
                      style: TextStyle(
                          fontSize: 18, color: AppTheme.textSecondary),
                    ),
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

class _PhoneRow extends StatelessWidget {
  final String label;
  final String phone;
  final Color color;
  final VoidCallback onCopy;

  const _PhoneRow({
    required this.label,
    required this.phone,
    required this.color,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(phone,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    letterSpacing: 1)),
          ),
          Semantics(
            button: true,
            label: 'Copiar número $label',
            child: GestureDetector(
              onTap: onCopy,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.copy_rounded,
                    color: AppTheme.primary, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
