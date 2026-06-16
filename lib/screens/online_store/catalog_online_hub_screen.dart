// Spec: specs/061-catalogo-online-hub/spec.md
// UI: specs/062-ui-highend-kit/spec.md (estética moderna, AppUI)
//
// Hub "Mi Catálogo Online": previsualizar el catálogo público,
// compartir/copiar el link, lanzar campañas masivas y editar el banner.
// Compone piezas existentes (link de tienda, marketing hub, constructor
// de promos). Refactor visual con el kit AppUI — solo presentación.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../promotions/promo_builder_screen.dart';
import '../promotions/promotions_list_screen.dart';

class CatalogOnlineHubScreen extends StatefulWidget {
  const CatalogOnlineHubScreen({super.key, ApiService? apiOverride})
      : _apiOverride = apiOverride;

  final ApiService? _apiOverride;

  @override
  State<CatalogOnlineHubScreen> createState() => _CatalogOnlineHubScreenState();
}

class _CatalogOnlineHubScreenState extends State<CatalogOnlineHubScreen> {
  late final ApiService _api =
      widget._apiOverride ?? ApiService(AuthService());

  String? _publicUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    try {
      final data = await _api.fetchStoreSlug();
      if (mounted) {
        setState(() {
          _publicUrl = (data['public_url'] as String?)?.trim();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _preview() async {
    final url = _publicUrl;
    if (url == null || url.isEmpty) return;
    HapticFeedback.lightImpact();
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('No se pudo abrir el catálogo.');
  }

  Future<void> _share() async {
    final url = _publicUrl;
    if (url == null || url.isEmpty) return;
    HapticFeedback.lightImpact();
    await Share.share(
      '🛍️ Mire nuestro catálogo en línea y haga su pedido: $url',
      subject: 'Nuestro catálogo en línea',
    );
  }

  void _copy() {
    final url = _publicUrl;
    if (url == null || url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.lightImpact();
    _snack('Link copiado');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  void _go(Widget screen) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + AppUI.s8;
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        title: 'Mi Catálogo Online',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(AppUI.s16, topPad, AppUI.s16, AppUI.s24),
        children: [
          _LinkCard(
            loading: _loading,
            publicUrl: _publicUrl,
            onPreview: _preview,
            onShare: _share,
            onCopy: _copy,
          ),
          const SizedBox(height: AppUI.s24),
          const Padding(
            padding: EdgeInsets.only(left: AppUI.s4, bottom: AppUI.s12),
            child: Text('Promociona tu catálogo', style: AppUI.sectionLabel),
          ),
          InsetGroupedList(
            children: [
              _ActionRow(
                icon: Icons.campaign_rounded,
                title: 'Envío masivo por campañas',
                onTap: () => _go(const PromotionsListScreen()),
              ),
              _ActionRow(
                icon: Icons.image_outlined,
                title: 'Editar banner y promociones',
                onTap: () => _go(const PromoBuilderScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.loading,
    required this.publicUrl,
    required this.onPreview,
    required this.onShare,
    required this.onCopy,
  });

  final bool loading;
  final String? publicUrl;
  final VoidCallback onPreview;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final hasLink = publicUrl != null && publicUrl!.isNotEmpty;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppUI.hairline,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: AppUI.s12),
              const Expanded(
                child: Text('Su catálogo en línea', style: AppUI.bodyStrong),
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: AppUI.s16),
            const Center(child: CircularProgressIndicator()),
          ] else if (hasLink) ...[
            const SizedBox(height: AppUI.s12),
            SelectableText(
              publicUrl!,
              key: const Key('catalog_hub_url'),
              style: const TextStyle(fontSize: 13, color: AppUI.inkSoft),
            ),
            const SizedBox(height: AppUI.s16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('catalog_hub_preview'),
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined, size: 20),
                label: const Text('Ver mi catálogo'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppUI.radius)),
                  textStyle:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: AppUI.s8),
            Row(
              children: [
                Expanded(
                  child: _GhostButton(
                    key: const Key('catalog_hub_share'),
                    icon: Icons.ios_share_rounded,
                    label: 'Compartir',
                    onTap: onShare,
                  ),
                ),
                const SizedBox(width: AppUI.s8),
                Expanded(
                  child: _GhostButton(
                    key: const Key('catalog_hub_copy'),
                    icon: Icons.link_rounded,
                    label: 'Copiar',
                    onTap: onCopy,
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: AppUI.s12),
            const Text(
              'Configure el enlace de su tienda en Perfil del Negocio.',
              style: AppUI.bodySoft,
            ),
          ],
        ],
      ),
    );
  }
}

/// Botón 'ghost' — fondo transparente, borde sutil, texto ink.
class _GhostButton extends StatelessWidget {
  const _GhostButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 19, color: AppUI.ink),
      label: Text(label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: AppUI.ink)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppUI.radius)),
      ),
    );
  }
}

/// Fila de acción dentro de la lista agrupada: ícono monocromo sutil +
/// título; sin subtítulo redundante. La interfaz se explica sola.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppUI.s16, vertical: AppUI.s12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppUI.hairline,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppUI.inkSoft),
            ),
            const SizedBox(width: AppUI.s16),
            Expanded(child: Text(title, style: AppUI.bodyStrong)),
            const Icon(Icons.chevron_right_rounded,
                color: AppUI.inkSoft, size: 22),
          ],
        ),
      ),
    );
  }
}
