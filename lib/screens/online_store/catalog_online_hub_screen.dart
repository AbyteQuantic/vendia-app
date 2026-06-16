// Spec: specs/061-catalogo-online-hub/spec.md
//
// Hub "Mi Catálogo Online": un solo lugar desde donde el tendero
// previsualiza su catálogo público, comparte/copia el link, lanza envíos
// masivos por campañas y edita el banner/promociones. Compone piezas que
// ya existían (link de tienda, marketing hub, constructor de promos) en
// una entrada prominente desde el Dashboard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../promotions/promo_builder_screen.dart';
import 'promo_management_screen.dart';

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
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _snack('No se pudo abrir el catálogo.');
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Mi Catálogo Online'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _LinkCard(
            loading: _loading,
            publicUrl: _publicUrl,
            onPreview: _preview,
            onShare: _share,
            onCopy: _copy,
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Promociona tu catálogo',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _ActionTile(
            icon: Icons.campaign_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Envío masivo por campañas',
            subtitle: 'Mande sus promociones por WhatsApp a sus clientes',
            onTap: () => _go(const PromoManagementScreen()),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.image_rounded,
            color: const Color(0xFFEA580C),
            title: 'Editar banner y promociones',
            subtitle: 'Cree combos y banners con IA para su catálogo',
            onTap: () => _go(const PromoBuilderScreen()),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDE8E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_rounded,
                    color: AppTheme.success, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Su catálogo en línea',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(),
              ),
            )
          else if (hasLink) ...[
            SelectableText(
              publicUrl!,
              key: const Key('catalog_hub_url'),
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            // Vista previa: acción principal, llamativa.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('catalog_hub_preview'),
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('Ver mi catálogo'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  minimumSize: const Size.fromHeight(50),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('catalog_hub_share'),
                    onPressed: onShare,
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('Compartir'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('catalog_hub_copy'),
                    onPressed: onCopy,
                    icon: const Icon(Icons.link_rounded, size: 20),
                    label: const Text('Copiar'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            const Text(
              'Configure el enlace de su tienda en Perfil del Negocio.',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEDE8E0)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
