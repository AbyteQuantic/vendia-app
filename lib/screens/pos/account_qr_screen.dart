import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vendia_pos/theme/app_theme.dart';

/// Screen that displays a QR code for the current account/table.
/// When the client scans it, they can see their bill in real-time,
/// request WhatsApp invoice, and suggest songs to the rockola.
class AccountQrScreen extends StatelessWidget {
  final String accountLabel; // e.g., "Mesa 4"
  final String cartLabel; // e.g., "C2 Activa"
  final String accountUuid;

  const AccountQrScreen({
    super.key,
    required this.accountLabel,
    required this.cartLabel,
    required this.accountUuid,
  });

  String get _qrUrl => 'https://vendia.com/cuenta/$accountUuid';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFBFF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 28),
          color: AppTheme.textPrimary,
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
          tooltip: 'Volver',
        ),
        title: Text(
          'QR de la Cuenta',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 16),
              // Account badge
              _buildAccountBadge(),
              const SizedBox(height: 24),
              // QR Code
              _buildQrCode(),
              const SizedBox(height: 20),
              // Instruction
              Text(
                'Muéstrele este código al cliente\npara que vea su cuenta en tiempo real',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // Features list
              _buildFeature(
                '📋',
                'Ve los productos y el total en vivo',
                const Color(0xFF10B981),
              ),
              const SizedBox(height: 10),
              _buildFeature(
                '📲',
                'Puede pedir su factura por WhatsApp',
                const Color(0xFF25D366),
              ),
              const SizedBox(height: 10),
              _buildFeature(
                '🎵',
                'Puede sugerir canciones a la rockola',
                const Color(0xFF764BA2),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667EEA).withValues(alpha: 0.08),
            const Color(0xFF764BA2).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF667EEA).withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.table_restaurant,
            size: 24,
            color: const Color(0xFF667EEA),
          ),
          const SizedBox(width: 8),
          Text(
            '$accountLabel · $cartLabel',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF667EEA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrCode() {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667EEA).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: QrImageView(
          data: _qrUrl,
          version: QrVersions.auto,
          size: 220,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF1A1A2E),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(String emoji, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
