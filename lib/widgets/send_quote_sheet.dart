// Spec: specs/031-cotizaciones/spec.md
//
// Bottom-sheet "Enviar cotización" (F031 — AC-06).
//
// Ofrece los canales de envío de una cotización ya guardada:
//   - WhatsApp  → abre wa.me con un mensaje precargado + link público.
//   - Copiar link → copia el URL público al portapapeles.
//   - Compartir → Share API nativo (share_plus).
//   - Imprimir / Guardar como PDF → abre el link público en el
//     navegador; la página dispara `window.print()` (vista print-ready).
//   - Ver QR → muestra el QR del link para que el cliente lo escanee.
//
// NOTA: el canal Email NO está aquí — es F032 (requiere infra SMTP).
//
// El sheet no llama al backend: recibe la [Quote] ya enviada y el host
// público; arma los enlaces y los abre. Quien lo invoca es responsable
// de haber llamado a `sendQuote` antes (la cotización debe tener
// `public_token`).
//
// Gerontodiseño: botones ≥56dp, textos ≥17pt, probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/quote.dart';
import '../theme/app_theme.dart';
import 'qr_code_dialog.dart';

/// Abre la bottom-sheet de envío de la cotización [quote].
///
/// [publicHost] es el origen del catálogo público (ej.
/// `https://tienda.vendia.store`). Si la cotización no tiene token aún,
/// el sheet muestra un estado de error en vez de canales rotos.
Future<void> showSendQuoteSheet(
  BuildContext context, {
  required Quote quote,
  required String publicHost,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SendQuoteSheet(quote: quote, publicHost: publicHost),
  );
}

class SendQuoteSheet extends StatelessWidget {
  final Quote quote;
  final String publicHost;

  const SendQuoteSheet({
    super.key,
    required this.quote,
    required this.publicHost,
  });

  /// URL público de la cotización. Vacío si falta el token.
  String get _url => quote.publicUrl(publicHost);

  /// Mensaje precargado para WhatsApp / compartir.
  String _message() {
    final folio = quote.folio.isNotEmpty ? quote.folio : 'cotización';
    return 'Hola${quote.customerName.isNotEmpty ? ' ${quote.customerName}' : ''}, '
        'le comparto su $folio. Puede revisarla aquí: $_url';
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    HapticFeedback.lightImpact();
    final text = Uri.encodeComponent(_message());
    final uri = Uri.parse('https://wa.me/?text=$text');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _snack(context, 'No se pudo abrir WhatsApp');
    }
  }

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (context.mounted) {
      _snack(context, 'Enlace copiado');
    }
  }

  Future<void> _share(BuildContext context) async {
    HapticFeedback.lightImpact();
    await Share.share(_message(), subject: 'Cotización ${quote.folio}');
  }

  Future<void> _openPrintView(BuildContext context) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse('$_url?print=1');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      _snack(context, 'No se pudo abrir la vista de impresión');
    }
  }

  void _showQr(BuildContext context) {
    HapticFeedback.lightImpact();
    showQrCodeDialog(
      context,
      url: _url,
      title: 'Escanee para ver la cotización',
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 2),
      ),
    );
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
              'Enviar cotización',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            if (quote.folio.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                quote.folio,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (!hasLink)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Esta cotización aún no tiene enlace público. '
                  'Guárdela y vuelva a intentar.',
                  style: TextStyle(
                    fontSize: 17,
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else ...[
              _ChannelButton(
                buttonKey: const Key('send_quote_whatsapp'),
                icon: Icons.chat_rounded,
                color: const Color(0xFF25D366),
                label: 'WhatsApp',
                subtitle: 'Mensaje listo con el enlace',
                onTap: () => _openWhatsApp(context),
              ),
              _ChannelButton(
                buttonKey: const Key('send_quote_copy'),
                icon: Icons.link_rounded,
                color: AppTheme.primary,
                label: 'Copiar enlace',
                subtitle: 'Pegue el enlace donde quiera',
                onTap: () => _copyLink(context),
              ),
              _ChannelButton(
                buttonKey: const Key('send_quote_share'),
                icon: Icons.share_rounded,
                color: AppTheme.primary,
                label: 'Compartir',
                subtitle: 'Use otra app de su teléfono',
                onTap: () => _share(context),
              ),
              _ChannelButton(
                buttonKey: const Key('send_quote_qr'),
                icon: Icons.qr_code_2_rounded,
                color: AppTheme.textPrimary,
                label: 'Mostrar código QR',
                subtitle: 'Para que el cliente lo escanee',
                onTap: () => _showQr(context),
              ),
              _ChannelButton(
                buttonKey: const Key('send_quote_print'),
                icon: Icons.print_rounded,
                color: AppTheme.warning,
                label: 'Imprimir / Guardar como PDF',
                subtitle: 'Elija "Guardar como PDF" en su navegador',
                onTap: () => _openPrintView(context),
              ),
            ],
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
