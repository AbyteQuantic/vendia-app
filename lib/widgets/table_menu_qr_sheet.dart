// Spec: specs/083-mesas-catalogo-qr/spec.md
//
// QR del MENÚ de una mesa: apunta al catálogo público con la mesa
// (`tienda.vendia.store/<slug>?mesa=<tableId>`). El comensal escanea, ve
// "Mesa X · Área" y pide desde la mesa. La URL es determinística (no necesita
// red para construirse), a diferencia del QR de cuenta-en-vivo (session token).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config/api_config.dart';
import '../theme/app_theme.dart';

/// Construye la URL pública del menú de una mesa.
String tableMenuUrl({required String slug, required String tableId}) =>
    '${ApiConfig.publicCatalogUrlFor(slug)}?mesa=$tableId';

Future<void> showTableMenuQrSheet(
  BuildContext context, {
  required String slug,
  required String tableId,
  required String tableLabel,
  String area = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TableMenuQrSheet(
      slug: slug,
      tableId: tableId,
      tableLabel: tableLabel,
      area: area,
    ),
  );
}

class _TableMenuQrSheet extends StatelessWidget {
  const _TableMenuQrSheet({
    required this.slug,
    required this.tableId,
    required this.tableLabel,
    required this.area,
  });

  final String slug;
  final String tableId;
  final String tableLabel;
  final String area;

  String get _url => tableMenuUrl(slug: slug, tableId: tableId);

  String get _heading =>
      area.isNotEmpty ? '$tableLabel · $area' : tableLabel;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enlace copiado'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _share() async {
    HapticFeedback.lightImpact();
    await Share.share(
      'Pida desde su mesa ($_heading): $_url',
      subject: 'Menú · $_heading',
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6D0C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Escanee para ver el menú de la mesa',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Text(
                _heading,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFEDE8E0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  key: const Key('table_menu_qr_image'),
                  data: _url,
                  version: QrVersions.auto,
                  size: 260,
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
                _url,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Imprima este QR y póngalo en la mesa. Los pedidos llegan a su '
                'Centro de Tareas con la mesa indicada.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('table_menu_qr_share'),
                  onPressed: _share,
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Compartir enlace'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Copiar enlace'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
