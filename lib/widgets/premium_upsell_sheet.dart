// Spec: specs/008-planes-suscripcion-epayco/spec.md
//
// Soft paywall + catálogo de planes. Reemplaza el placeholder anterior
// (que abría un `wa.me` ficticio) por el flujo real de Feature 008:
// muestra el catálogo Gratis / Pro y, al activar Pro, pide el checkout
// de ePayco al backend y abre la pasarela. Al volver del checkout
// refresca el estado de la suscripción (`/subscription/status`).
//
// El webhook de ePayco es la fuente de verdad de la promoción a Pro
// (spec D2); este widget solo abre el checkout — no decide nada.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/subscription.dart';
import '../services/api_service.dart';
import '../services/app_error.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Resultado de abrir la pasarela de pago. Permite que un test
/// inyecte la apertura sin tocar `url_launcher` ni la red.
typedef CheckoutLauncher = Future<bool> Function(Uri url);

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
///
/// [api] y [launcher] se inyectan en tests; en producción quedan en
/// `null` y el sheet usa el cliente HTTP real y `url_launcher`.
Future<void> showPremiumUpsellSheet(
  BuildContext context, {
  String? reason,
  ApiService? api,
  CheckoutLauncher? launcher,
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
    // En escritorio el modal por defecto se limita a 640dp de ancho;
    // ampliamos el tope a 920dp para que la comparación Gratis vs Pro
    // pueda mostrarse con las tarjetas lado a lado (F009 D4). En móvil
    // (360dp) el `BoxConstraints` no recorta nada — la hoja sigue a
    // todo el ancho y las tarjetas se apilan.
    constraints: const BoxConstraints(maxWidth: 920),
    builder: (_) => _PremiumUpsellSheet(
      reason: reason,
      api: api,
      launcher: launcher,
    ),
  );
}

/// Abre la URL del checkout de ePayco. En web hace `launchUrl` en la
/// misma pestaña (redirect); en móvil abre el navegador externo. Es la
/// implementación por defecto de [CheckoutLauncher].
Future<bool> _defaultLaunchCheckout(Uri url) {
  return launchUrl(
    url,
    // Web: redirige la pestaña actual al checkout (`_self`). Móvil:
    // navegador externo para que el usuario complete el pago y vuelva.
    mode: kIsWeb
        ? LaunchMode.platformDefault
        : LaunchMode.externalApplication,
    webOnlyWindowName: kIsWeb ? '_self' : null,
  );
}

class _PremiumUpsellSheet extends StatefulWidget {
  const _PremiumUpsellSheet({this.reason, this.api, this.launcher});

  final String? reason;
  final ApiService? api;
  final CheckoutLauncher? launcher;

  @override
  State<_PremiumUpsellSheet> createState() => _PremiumUpsellSheetState();
}

enum _LoadState { loading, ready, error }

class _PremiumUpsellSheetState extends State<_PremiumUpsellSheet> {
  late final ApiService _api;
  late final CheckoutLauncher _launcher;

  _LoadState _state = _LoadState.loading;
  String? _loadError;

  List<SubscriptionPlan> _plans = const [];

  /// Estado de suscripción del tenant. Alimenta el contador de prueba
  /// prominente (F009). `null` si el tenant no está en prueba o si su
  /// fetch falló — en ese caso simplemente no se muestra el contador.
  SubscriptionStatus? _status;

  /// Intervalo elegido para el plan Pro (`mensual` | `anual`).
  String _selectedInterval = BillingInterval.mensual;

  /// `true` mientras se pide el checkout de ePayco al backend.
  bool _checkoutInFlight = false;

  /// Mensaje de error del intento de checkout (se muestra inline).
  String? _checkoutError;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiService(AuthService());
    _launcher = widget.launcher ?? _defaultLaunchCheckout;
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _state = _LoadState.loading;
      _loadError = null;
    });
    try {
      final plans = await _api.fetchPlans();
      // El estado de suscripción alimenta el contador de prueba
      // (F009). Su fallo NO bloquea el catálogo: si no llega, el
      // contador simplemente no se muestra — los planes sí.
      final status = await _loadStatusBestEffort();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _status = status;
        _state = _LoadState.ready;
      });
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _state = _LoadState.error;
      });
    } catch (e) {
      // No tragamos errores en silencio (regla de la feature): un
      // fallo inesperado se muestra con copia genérica en español.
      if (!mounted) return;
      setState(() {
        _loadError =
            'No pudimos cargar los planes. Revisa tu conexión e intenta de nuevo.';
        _state = _LoadState.error;
      });
    }
  }

  /// Carga el estado de suscripción sin que su fallo tumbe el catálogo
  /// (F009). Devuelve `null` ante cualquier error — el contador de
  /// prueba simplemente no se dibuja. No se traga el error: se reporta
  /// por consola para diagnóstico.
  Future<SubscriptionStatus?> _loadStatusBestEffort() async {
    try {
      return await _api.fetchSubscriptionStatus();
    } on AppError catch (e) {
      debugPrint('PremiumUpsellSheet: no se pudo cargar el estado de '
          'suscripción: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('PremiumUpsellSheet: error inesperado al cargar el '
          'estado de suscripción: $e');
      return null;
    }
  }

  SubscriptionPlan? get _proPlan {
    for (final plan in _plans) {
      if (plan.id == PlanId.pro) return plan;
    }
    return null;
  }

  /// Pide el checkout de ePayco, abre la pasarela y, al volver,
  /// refresca el estado de la suscripción.
  Future<void> _activatePro() async {
    final pro = _proPlan;
    if (pro == null) {
      setState(() {
        _checkoutError =
            'El plan Pro no está disponible en este momento.';
      });
      return;
    }

    setState(() {
      _checkoutInFlight = true;
      _checkoutError = null;
    });

    try {
      HapticFeedback.lightImpact();
    } catch (_) {}

    try {
      final session = await _api.createCheckout(
        plan: PlanId.pro,
        interval: _selectedInterval,
      );

      final uri = _checkoutUri(session);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _checkoutInFlight = false;
          _checkoutError =
              'No recibimos un enlace de pago válido. Intenta de nuevo.';
        });
        return;
      }

      final opened = await _launcher(uri);
      if (!opened) {
        if (!mounted) return;
        setState(() {
          _checkoutInFlight = false;
          _checkoutError =
              'No pudimos abrir la pasarela de pago. Intenta de nuevo.';
        });
        return;
      }

      // El usuario fue enviado al checkout de ePayco. Al volver a la
      // app refrescamos el estado: el webhook de ePayco ya lo habrá
      // promovido a PRO_ACTIVE si el pago se confirmó (D2).
      if (!mounted) return;
      setState(() => _checkoutInFlight = false);
      await _refreshStatusAfterCheckout();
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() {
        _checkoutInFlight = false;
        _checkoutError = e.message;
      });
    } catch (e) {
      // PROHIBIDO `catch (_)` que trague el error — lo reportamos.
      if (!mounted) return;
      setState(() {
        _checkoutInFlight = false;
        _checkoutError =
            'No pudimos iniciar el pago. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  /// Construye la URL del checkout: usa la URL directa si el backend
  /// la entregó; si no, no hay nada que abrir.
  Uri? _checkoutUri(CheckoutSession session) {
    if (!session.hasUrl) return null;
    return Uri.tryParse(session.checkoutUrl);
  }

  /// Vuelve a consultar `/subscription/status` tras el checkout. Si el
  /// tenant ya quedó en Pro lo mostramos y cerramos el sheet.
  Future<void> _refreshStatusAfterCheckout() async {
    try {
      final status = await _api.fetchSubscriptionStatus();
      if (!mounted) return;

      if (status.isPremium && !status.isTrial) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              '¡Listo! Tu plan Pro quedó activo.',
              style: TextStyle(fontSize: 16),
            ),
            backgroundColor: AppTheme.primary,
          ),
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        // El webhook puede tardar unos segundos. Avisamos sin tragar
        // el caso: el usuario sabe que el pago se confirma aparte.
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Estamos confirmando tu pago. Si ya pagaste, tu plan Pro se '
              'activará en unos minutos.',
              style: TextStyle(fontSize: 15),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } on AppError catch (e) {
      if (!mounted) return;
      setState(() => _checkoutError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checkoutError =
            'No pudimos verificar tu suscripción. Vuelve a abrir esta '
            'pantalla en unos minutos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
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
              _grabber(),
              _header(),
              const SizedBox(height: 20),
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grabber() {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
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
              Text('Elige tu plan y activa todas las herramientas',
                  style: TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _body() {
    switch (_state) {
      case _LoadState.loading:
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              key: Key('premium_upsell_loading'),
              child: CircularProgressIndicator(),
            ),
          ),
        ];
      case _LoadState.error:
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              key: const Key('premium_upsell_load_error'),
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: AppTheme.textSecondary, size: 40),
                const SizedBox(height: 12),
                Text(
                  _loadError ??
                      'No pudimos cargar los planes. Intenta de nuevo.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  key: const Key('premium_upsell_retry'),
                  onPressed: _loadCatalog,
                  child: const Text('Reintentar',
                      style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ];
      case _LoadState.ready:
        return _catalog();
    }
  }

  List<Widget> _catalog() {
    final pro = _proPlan;
    final widgets = <Widget>[];

    // Contador de prueba prominente (F009): solo cuando el tenant
    // está en TRIAL. Va arriba de todo para que el usuario vea
    // primero cuánto tiempo le queda.
    final status = _status;
    if (status != null && status.isTrial) {
      widgets.add(_TrialCounterBanner(status: status));
      widgets.add(const SizedBox(height: 16));
    }

    if (widget.reason != null) {
      widgets.add(
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            widget.reason!,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }

    // Comparación Gratis vs Pro (F009). Responsive: en ancho de
    // escritorio (≥ 600dp) las tarjetas van lado a lado; en móvil
    // (360dp) se apilan. `LayoutBuilder` mide el ancho disponible —
    // sin anchos fijos (regla mobile-first del frontend).
    final gratisCard = _FreePlanCard(plan: _gratisPlan());
    final proCard = pro != null
        ? _ProPlanCard(
            plan: pro,
            selectedInterval: _selectedInterval,
            onIntervalChanged: (interval) {
              setState(() {
                _selectedInterval = interval;
                _checkoutError = null;
              });
            },
          )
        : const _ProUnavailableCard();

    widgets.add(
      LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 600;
          if (sideBySide) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: gratisCard),
                  const SizedBox(width: 14),
                  Expanded(child: proCard),
                ],
              ),
            );
          }
          return Column(
            children: [
              gratisCard,
              const SizedBox(height: 14),
              proCard,
            ],
          );
        },
      ),
    );

    if (_checkoutError != null) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(
        Container(
          key: const Key('premium_upsell_checkout_error'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppTheme.error, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _checkoutError!,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.error),
                ),
              ),
            ],
          ),
        ),
      );
    }

    widgets.add(const SizedBox(height: 20));
    widgets.add(_proCta(pro));
    widgets.add(const SizedBox(height: 8));
    widgets.add(
      TextButton(
        key: const Key('premium_upsell_dismiss'),
        onPressed: _checkoutInFlight
            ? null
            : () => Navigator.of(context).pop(),
        child: const Text('Seguir con el plan gratis',
            style: TextStyle(fontSize: 16)),
      ),
    );

    return widgets;
  }

  Widget _proCta(SubscriptionPlan? pro) {
    final price = pro?.priceFor(_selectedInterval);
    final label = price == null
        ? 'Activar VendIA PRO'
        : 'Pagar ${_formatCop(price.amount)} y activar PRO';

    return ElevatedButton(
      key: const Key('premium_upsell_cta'),
      onPressed:
          (_checkoutInFlight || pro == null) ? null : _activatePro,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor:
            AppTheme.primary.withValues(alpha: 0.5),
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
      ),
      child: _checkoutInFlight
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(label,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700)),
    );
  }

  /// Devuelve el plan Gratis del catálogo, o uno por defecto si el
  /// backend no lo envió (para no dejar la tarjeta vacía).
  SubscriptionPlan _gratisPlan() {
    for (final plan in _plans) {
      if (plan.id == PlanId.gratis) return plan;
    }
    return const SubscriptionPlan(
      id: PlanId.gratis,
      name: 'Gratis',
      description: 'Lo esencial para vender',
      prices: [PlanPrice(interval: BillingInterval.mensual, amount: 0)],
      features: [
        'Registrar ventas',
        'Ver tu inventario',
      ],
    );
  }
}

/// Formatea un monto en COP con separador de miles colombiano.
/// Ej: 29900 → "$29.900".
String _formatCop(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '\$$buffer';
}

/// Tarjeta del plan Gratis — informativa, sin acción.
class _FreePlanCard extends StatelessWidget {
  const _FreePlanCard({required this.plan});
  final SubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('plan_card_gratis'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name.isEmpty ? 'Gratis' : plan.name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                ),
              ),
              const Text(
                '\$0',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.description.isEmpty
                ? 'Sigues pudiendo vender y ver tu inventario.'
                : plan.description,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
          if (plan.features.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _ComparisonHeading(text: 'Incluye:'),
            ...plan.features.map(
              (f) => _PlanFeatureRow(text: f, highlighted: false),
            ),
          ],
        ],
      ),
    );
  }
}

/// Encabezado pequeño de la lista de funciones dentro de una tarjeta
/// de plan — separa visualmente "qué incluye" del nombre/precio.
class _ComparisonHeading extends StatelessWidget {
  const _ComparisonHeading({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Tarjeta que se muestra en lugar del plan Pro cuando el backend no
/// lo devolvió — mantiene la comparación con dos columnas en vez de
/// dejar un hueco.
class _ProUnavailableCard extends StatelessWidget {
  const _ProUnavailableCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('plan_card_pro'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary, width: 1.5),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_rounded,
                  color: AppTheme.primary, size: 22),
              SizedBox(width: 8),
              Text('Pro',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'El plan Pro no está disponible por ahora. Intenta de '
            'nuevo en unos minutos.',
            style:
                TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Banner del contador de prueba prominente (F009) — se muestra arriba
/// de la comparación de planes cuando el tenant está en TRIAL. Incluye
/// la barra de progreso días-usados/total y la etiqueta en español.
class _TrialCounterBanner extends StatelessWidget {
  const _TrialCounterBanner({required this.status});
  final SubscriptionStatus status;

  @override
  Widget build(BuildContext context) {
    final remaining = status.trialDaysRemaining;
    final dayWord = remaining == 1 ? 'día' : 'días';

    return Container(
      key: const Key('premium_upsell_trial_counter'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.12),
            AppTheme.primaryLight.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Te quedan $remaining $dayWord de prueba Pro',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              key: const Key('premium_upsell_trial_progress'),
              value: status.trialProgress,
              minHeight: 8,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.primary),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Disfruta todas las herramientas Pro mientras dura tu '
            'prueba. Elige un plan para no perderlas.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta del plan Pro — con selector de intervalo mensual/anual.
class _ProPlanCard extends StatelessWidget {
  const _ProPlanCard({
    required this.plan,
    required this.selectedInterval,
    required this.onIntervalChanged,
  });

  final SubscriptionPlan plan;
  final String selectedInterval;
  final ValueChanged<String> onIntervalChanged;

  @override
  Widget build(BuildContext context) {
    final monthly = plan.priceFor(BillingInterval.mensual);
    final yearly = plan.priceFor(BillingInterval.anual);
    final selectedPrice = plan.priceFor(selectedInterval);

    return Container(
      key: const Key('plan_card_pro'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.name.isEmpty ? 'Pro' : plan.name,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.description.isEmpty
                ? 'Todas las herramientas para hacer crecer tu negocio.'
                : plan.description,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          // Selector mensual / anual.
          Row(
            children: [
              if (monthly != null)
                Expanded(
                  child: _IntervalChip(
                    keyValue: 'interval_mensual',
                    title: 'Mensual',
                    subtitle: '${_formatCop(monthly.amount)} / mes',
                    selected: selectedInterval ==
                        BillingInterval.mensual,
                    onTap: () => onIntervalChanged(
                        BillingInterval.mensual),
                  ),
                ),
              if (monthly != null && yearly != null)
                const SizedBox(width: 10),
              if (yearly != null)
                Expanded(
                  child: _IntervalChip(
                    keyValue: 'interval_anual',
                    title: 'Anual',
                    subtitle: '${_formatCop(yearly.amount)} / año',
                    selected:
                        selectedInterval == BillingInterval.anual,
                    onTap: () =>
                        onIntervalChanged(BillingInterval.anual),
                  ),
                ),
            ],
          ),
          if (selectedPrice != null) ...[
            const SizedBox(height: 12),
            Text(
              'Pagas ${_formatCop(selectedPrice.amount)} '
              '${selectedInterval == BillingInterval.anual ? 'al año' : 'al mes'}.',
              key: const Key('pro_selected_price'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
            ),
          ],
          // Las funciones llegan del catálogo del backend (F009 §8).
          // Ya no hay viñetas hardcodeadas: si el backend no envía
          // funciones, mostramos un texto neutral en vez de una lista
          // inexacta.
          const SizedBox(height: 12),
          const _ComparisonHeading(text: 'Todo lo de Gratis, y además:'),
          if (plan.features.isNotEmpty)
            ...plan.features.map(
              (f) => _PlanFeatureRow(text: f, highlighted: true),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Estamos cargando las funciones de este plan.',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chip seleccionable para elegir el intervalo de facturación.
class _IntervalChip extends StatelessWidget {
  const _IntervalChip({
    required this.keyValue,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String keyValue;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key(keyValue),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.16)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : const Color(0xFFE5E7EB),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // FittedBox: en 360dp el chip mide ~100dp; el ícono +
            // título se escalan hacia abajo en vez de hacer overflow.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: selected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de un beneficio del plan con check.
class _PlanFeatureRow extends StatelessWidget {
  const _PlanFeatureRow({required this.text, required this.highlighted});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            highlighted
                ? Icons.check_circle_rounded
                : Icons.check_circle_outline_rounded,
            size: 18,
            color: highlighted
                ? AppTheme.primary
                : AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
