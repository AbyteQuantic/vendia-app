import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Soft paywall shown when the backend returns `403 premium_expired`.
/// The design intent: persuade, don't block — basic operations (vender,
/// ver inventario físico) are still available, so the cashier can
/// keep serving customers while the owner decides whether to upgrade.
///
/// The sheet is idempotent — [PremiumUpsellController.notifyBlocked]
/// short-circuits while a sheet is already on screen so a burst of
/// 403s from the same tenant doesn't stack modals.
class PremiumUpsellController {
  PremiumUpsellController._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Set by test harnesses to intercept the show call without
  /// rendering the real sheet. Production leaves this null and the
  /// controller falls through to showModalBottomSheet.
  @visibleForTesting
  static Future<void> Function(BuildContext context, String? reason)?
      showOverride;

  static bool _isShowing = false;

  /// Test-only: reset the "sheet currently showing" guard so tests
  /// don't leak state between each other.
  @visibleForTesting
  static void resetForTest() {
    _isShowing = false;
  }

  /// Called by the Dio interceptor when a `premium_expired` response
  /// lands. Triggers the bottom sheet at most once per burst.
  static Future<void> notifyBlocked({String? reason}) async {
    if (_isShowing) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    _isShowing = true;
    try {
      if (showOverride != null) {
        await showOverride!(context, reason);
      } else {
        await showPremiumUpsellSheet(context, reason: reason);
      }
    } finally {
      _isShowing = false;
    }
  }
}

/// Renders the upsell sheet. Public so tests can pump it directly and
/// so screens can surface it proactively (e.g. from a "Ver todos los
/// módulos PRO" button on the admin hub).
Future<void> showPremiumUpsellSheet(
  BuildContext context, {
  String? reason,
}) {
  // HapticFeedback hits a platform channel that isn't mocked in widget
  // tests — swallow so a CI run doesn't fail on the UI smoke test.
  try {
    HapticFeedback.mediumImpact();
  } catch (_) {}
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PremiumUpsellSheet(reason: reason),
  );
}

class _PremiumUpsellSheet extends StatelessWidget {
  const _PremiumUpsellSheet({this.reason});
  final String? reason;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        key: const Key('premium_upsell_sheet'),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded,
                        color: AppTheme.primary, size: 32),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('VendIA PRO',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary)),
                        SizedBox(height: 2),
                        Text('Tu prueba terminó — sigue vendiendo con todas las herramientas',
                            style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _FeatureBullet(
                icon: Icons.insights_rounded,
                title: 'Reportes y analíticas',
                body: 'Mira cuánto vendiste hoy, esta semana y tus top productos.',
              ),
              const _FeatureBullet(
                icon: Icons.menu_book_rounded,
                title: 'Fiar a tus clientes',
                body: 'Lleva las cuentas, envía recordatorios por WhatsApp.',
              ),
              const _FeatureBullet(
                icon: Icons.cloud_sync_rounded,
                title: 'Respaldo en la nube',
                body: 'Tus ventas sincronizadas aunque se apague el celular.',
              ),
              const _FeatureBullet(
                icon: Icons.storefront_rounded,
                title: 'Módulos premium',
                body: 'Mesas, KDS, cobros por servicios y combos con IA.',
              ),
              const SizedBox(height: 16),
              Text(
                reason ?? 'Sigues pudiendo vender y ver tu inventario sin plan PRO.',
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                key: const Key('premium_upsell_cta'),
                onPressed: () async {
                  try {
                    HapticFeedback.lightImpact();
                  } catch (_) {}
                  // Deep link target is configurable later — for now we
                  // drop into wa.me with a pre-seeded message so the
                  // sales team can close manually while the billing UI
                  // is still being built (Phase 2).
                  final uri = Uri.parse(
                    'https://wa.me/573001112233?text=${Uri.encodeComponent(
                      'Hola, quiero activar VendIA PRO',
                    )}',
                  );
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (context.mounted) Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text('Activar VendIA PRO',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('premium_upsell_dismiss'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Seguir con el plan gratis',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
