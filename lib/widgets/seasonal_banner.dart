// Spec: specs/086-branding-estacional/spec.md
//
// Banner estacional (server-driven) sobre la grilla del Dashboard. Fail-safe:
// si no hay temporada o banner → SizedBox.shrink(). Descartable y la dismissal
// persiste por campaña (no vuelve a aparecer hasta otra temporada).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/seasonal_branding_controller.dart';
import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

class SeasonalBanner extends StatefulWidget {
  const SeasonalBanner({super.key});

  @override
  State<SeasonalBanner> createState() => _SeasonalBannerState();
}

class _SeasonalBannerState extends State<SeasonalBanner> {
  static const _kDismissed = 'vendia_season_banner_dismissed';
  String? _dismissedKey;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedKey = prefs.getString(_kDismissed);
    } catch (_) {/* ignora */}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _dismiss(String key) async {
    HapticFeedback.lightImpact();
    setState(() => _dismissedKey = key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDismissed, key);
    } catch (_) {/* ignora */}
  }

  @override
  Widget build(BuildContext context) {
    final b = watchSeasonalBranding(context);
    if (!_loaded || !b.hasBanner || _dismissedKey == b.key) {
      return const SizedBox.shrink();
    }
    final bg = b.bannerBg ?? AppTheme.primary;
    final fg = _contrastOn(bg);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s12),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppUI.radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: b.bannerLinkUrl == null ? null : () => _open(b.bannerLinkUrl!),
          child: Padding(
            padding: const EdgeInsets.all(AppUI.s12),
            child: Row(
              children: [
                if (b.bannerImageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppUI.radiusSm),
                    child: Image.network(
                      b.bannerImageUrl!,
                      width: 44, height: 44, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: AppUI.s12),
                ],
                Expanded(
                  child: Text(
                    b.bannerText ?? b.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 20, color: fg),
                  onPressed: () => _dismiss(b.key),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Blanco o tinta según luminancia del fondo (contraste legible AA).
  Color _contrastOn(Color bg) =>
      bg.computeLuminance() > 0.5 ? AppTheme.textPrimary : Colors.white;
}
