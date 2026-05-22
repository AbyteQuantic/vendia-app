// Spec: specs/031-cotizaciones/spec.md
//
// Diálogo que muestra el código QR de un enlace público (F031).
//
// Lo usa la bottom-sheet "Enviar cotización" cuando el dueño quiere
// que el cliente escanee el link en vez de copiarlo: muestra el QR
// grande y centrado con el URL debajo.
//
// Gerontodiseño: QR grande (240dp), texto del URL seleccionable.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';

/// Abre un diálogo con el QR del [url] indicado.
Future<void> showQrCodeDialog(
  BuildContext context, {
  required String url,
  String title = 'Escanee para abrir',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => QrCodeDialog(url: url, title: title),
  );
}

class QrCodeDialog extends StatelessWidget {
  final String url;
  final String title;

  const QrCodeDialog({
    super.key,
    required this.url,
    this.title = 'Escanee para abrir',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: QrImageView(
                key: const Key('quote_qr_image'),
                data: url,
                version: QrVersions.auto,
                size: 240,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppTheme.primary,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              url,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('quote_qr_close'),
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Cerrar',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
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
