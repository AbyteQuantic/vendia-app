// Spec: specs/069-catalogo-unificado-eventos-inventario/spec.md
//
// Tarjeta "Su catálogo en línea": muestra el link público del comercio con
// botones Copiar y Abrir. Acceso directo al catálogo desde cualquier módulo
// (inventario, etc.), como ya lo tienen otros. Se oculta sola si no hay slug.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../theme/app_ui.dart';
import '../theme/app_theme.dart';

class CatalogLinkCard extends StatelessWidget {
  /// store_slug del comercio (de fetchStoreConfig). Vacío → no se muestra.
  final String storeSlug;
  final String keyPrefix;

  const CatalogLinkCard({
    super.key,
    required this.storeSlug,
    this.keyPrefix = 'catalog_preview',
  });

  String get _url =>
      storeSlug.isEmpty ? '' : ApiConfig.publicCatalogUrlFor(storeSlug);

  @override
  Widget build(BuildContext context) {
    if (storeSlug.isEmpty) return const SizedBox.shrink();
    final url = _url;
    return SoftCard(
      child: Row(
        children: [
          const Icon(Icons.public_rounded, color: AppTheme.primary, size: 20),
          const SizedBox(width: AppUI.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Su catálogo en línea', style: AppUI.sectionLabel),
                Text(url.replaceFirst('https://', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.bodyStrong),
              ],
            ),
          ),
          IconButton(
            key: Key('${keyPrefix}_copy'),
            icon: const Icon(Icons.copy_rounded, size: 20, color: AppUI.inkSoft),
            tooltip: 'Copiar link',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Link copiado', style: TextStyle(fontSize: 15)),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
          ),
          IconButton(
            key: Key('${keyPrefix}_open'),
            icon: const Icon(Icons.open_in_new_rounded,
                size: 20, color: AppTheme.primary),
            tooltip: 'Abrir catálogo',
            onPressed: () async {
              await launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
    );
  }
}
