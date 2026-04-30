import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vendia_pos/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

/// Screen that displays a QR code for the current account/table.
/// Resolves the public URL dynamically via fetchStoreSlug + session_token.
class AccountQrScreen extends StatefulWidget {
  final String accountLabel; // e.g., "Mesa 4" or "C2"
  final String cartLabel; // e.g., "Cuenta Activa"
  final String accountUuid;

  const AccountQrScreen({
    super.key,
    required this.accountLabel,
    required this.cartLabel,
    required this.accountUuid,
  });

  @override
  State<AccountQrScreen> createState() => _AccountQrScreenState();
}

class _AccountQrScreenState extends State<AccountQrScreen> {
  String? _qrUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveUrl();
  }

  Future<void> _resolveUrl() async {
    try {
      final api = ApiService(AuthService());
      final slugData = await api.fetchStoreSlug();
      final baseUrl = (slugData['base_url'] as String?)?.trim();

      if (baseUrl == null || baseUrl.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'No encontramos el dominio de tu tienda. '
                'Configúralo en Marketing > Catalogo Online.';
          });
        }
        return;
      }

      // Try to resolve session_token for the table
      String? token;
      try {
        final ticket = await api.fetchOpenTicketByLabel(widget.accountLabel);
        token = (ticket?['session_token'] as String?)?.trim();
      } catch (_) {}

      if (!mounted) return;

      final origin = _originOf(baseUrl);
      final url = token != null && token.isNotEmpty
          ? '$origin/t/$token'
          : '$origin/cuenta/${widget.accountUuid}';

      setState(() {
        _qrUrl = url;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error al cargar QR: $e';
      });
    }
  }

  String _originOf(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return raw;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  Future<void> _share() async {
    if (_qrUrl == null) return;
    HapticFeedback.lightImpact();
    await Share.share(
      'Tu cuenta en ${widget.accountLabel}: $_qrUrl',
      subject: 'Cuenta ${widget.accountLabel}',
    );
  }

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
        ),
        title: const Text(
          'QR de la Cuenta',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, color: AppTheme.textSecondary)),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        _buildAccountBadge(),
                        const SizedBox(height: 24),
                        _buildQrCode(),
                        const SizedBox(height: 20),
                        Text(
                          'Muestrele este codigo al cliente\npara que vea su cuenta en tiempo real',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_qrUrl != null)
                          SelectableText(
                            _qrUrl!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _share,
                            icon: const Icon(Icons.share_rounded),
                            label: const Text('Compartir enlace'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildFeature(
                            Icons.receipt_long_rounded,
                            'Ve los productos y el total en vivo',
                            const Color(0xFF10B981)),
                        const SizedBox(height: 10),
                        _buildFeature(
                            Icons.chat_rounded,
                            'Puede pedir su factura por WhatsApp',
                            const Color(0xFF25D366)),
                        const SizedBox(height: 10),
                        _buildFeature(
                            Icons.music_note_rounded,
                            'Puede sugerir canciones a la rockola',
                            const Color(0xFF764BA2)),
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
          const Icon(Icons.table_restaurant, size: 24, color: Color(0xFF667EEA)),
          const SizedBox(width: 8),
          Text(
            '${widget.accountLabel} · ${widget.cartLabel}',
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
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
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
          data: _qrUrl ?? '',
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

  Widget _buildFeature(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}
