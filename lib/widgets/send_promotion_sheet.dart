// Spec: specs/033-difusion-promociones/spec.md
//
// Bottom-sheet "Enviar promoción" (F033 — spec §4 "Enviar", AC-07/08).
//
// Ofrece los 3 canales de difusión de una promoción ya guardada (mismo
// patrón que la bottom-sheet de cotizaciones de F031):
//
//   1. WhatsApp en cola asistida → la pantalla de cola modo express.
//   2. Link público + QR → copia el link / muestra el QR escaneable.
//   3. Compartir nativo → Share API.
//
// El sheet no llama al backend: recibe la promoción ya guardada con su
// `public_token` y dispara los callbacks. Quien lo invoca
// (promotion_detail_screen) decide qué hacer con WhatsApp (necesita
// elegir audiencia primero).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/broadcast_promotion.dart';
import '../theme/app_theme.dart';
import 'qr_code_dialog.dart';

/// Abre la bottom-sheet de envío de la promoción [promotion].
///
/// [onWhatsAppQueue] se dispara cuando el dueño elige el canal WhatsApp
/// — el llamador navega al selector de audiencia + la cola.
/// [publicHost] es el origen del link público (ej.
/// `https://tienda.vendia.store`).
Future<void> showSendPromotionSheet(
  BuildContext context, {
  required BroadcastPromotion promotion,
  required String publicHost,
  required VoidCallback onWhatsAppQueue,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SendPromotionSheet(
      promotion: promotion,
      publicHost: publicHost,
      onWhatsAppQueue: onWhatsAppQueue,
    ),
  );
}

class SendPromotionSheet extends StatelessWidget {
  final BroadcastPromotion promotion;
  final String publicHost;
  final VoidCallback onWhatsAppQueue;

  const SendPromotionSheet({
    super.key,
    required this.promotion,
    required this.publicHost,
    required this.onWhatsAppQueue,
  });

  /// URL pública de la promoción. Vacío si falta el token.
  String get _url => promotion.publicUrl(publicHost);

  /// Mensaje para el canal "Compartir nativo".
  String _shareMessage() {
    final title = promotion.title.isNotEmpty
        ? promotion.title
        : 'nuestra promoción';
    return '$title 👇 $_url';
  }

  void _onWhatsApp(BuildContext context) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
    onWhatsAppQueue();
  }

  Future<void> _copyLink(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: _url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enlace copiado',
              style: TextStyle(fontSize: 16)),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showQr(BuildContext context) {
    HapticFeedback.lightImpact();
    showQrCodeDialog(
      context,
      url: _url,
      title: 'Escanee para ver la promoción',
    );
  }

  Future<void> _share(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Share.share(_shareMessage(),
        subject: promotion.title);
  }

  @override
  Widget build(BuildContext context) {
    final hasLink = _url.isNotEmpty;
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D0C8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Enviar promoción',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _ChannelButton(
              buttonKey: const Key('send_promo_whatsapp'),
              icon: Icons.chat_rounded,
              color: const Color(0xFF25D366),
              label: 'WhatsApp en cola',
              subtitle: 'Avise uno por uno en modo express',
              onTap: () => _onWhatsApp(context),
            ),
            if (hasLink) ...[
              _ChannelButton(
                buttonKey: const Key('send_promo_copy'),
                icon: Icons.link_rounded,
                color: AppTheme.primary,
                label: 'Copiar enlace',
                subtitle: 'Péguelo en su estado o donde quiera',
                onTap: () => _copyLink(context),
              ),
              _ChannelButton(
                buttonKey: const Key('send_promo_qr'),
                icon: Icons.qr_code_2_rounded,
                color: AppTheme.textPrimary,
                label: 'Mostrar código QR',
                subtitle: 'Para imprimir o que lo escaneen',
                onTap: () => _showQr(context),
              ),
              _ChannelButton(
                buttonKey: const Key('send_promo_share'),
                icon: Icons.share_rounded,
                color: AppTheme.primary,
                label: 'Compartir',
                subtitle: 'Use otra app de su teléfono',
                onTap: () => _share(context),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'El enlace público aún no está listo. Guarde la '
                  'promoción y vuelva a intentar.',
                  style: TextStyle(
                      fontSize: 16, color: AppTheme.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila de un canal de envío — ícono coloreado + título + subtítulo.
class _ChannelButton extends StatelessWidget {
  final Key buttonKey;
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ChannelButton({
    required this.buttonKey,
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textSecondary, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
