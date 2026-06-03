// Spec: specs/009-trial-visible-vista-planes/spec.md
//
// Indicador de prueba para el header del Dashboard (Feature 009).
// Consume `GET /subscription/status` y, según el estado del tenant,
// muestra:
//   - TRIAL      → barra de progreso (días usados / total) + etiqueta
//                  "Te quedan N días de prueba Pro".
//   - FREE       → prompt compacto "Activa Pro" (el trial venció).
//   - PRO_ACTIVE → nada (`SizedBox.shrink`).
//
// Tocar la barra/prompt abre la vista de planes (`showPremiumUpsellSheet`).
//
// Regla de la feature: si el fetch de estado falla, la barra NO se
// muestra — no bloquea ni rompe el Dashboard. El error se registra,
// no se traga en silencio (ver `_loadStatus`).

import 'package:flutter/material.dart';

import '../models/subscription.dart';
import '../services/api_service.dart';
import '../services/app_error.dart';
import '../services/auth_service.dart';
import 'premium_upsell_sheet.dart';

/// Barra del trial montada en el header del Dashboard.
///
/// [api] y [onOpenPlans] se inyectan en tests; en producción quedan en
/// `null` y la barra usa el `ApiService` real y abre el bottom sheet
/// de planes de F008.
class TrialBar extends StatefulWidget {
  const TrialBar({
    super.key,
    this.api,
    this.onOpenPlans,
    this.status,
    this.selfLoad = true,
  });

  /// Cliente HTTP. `null` en producción → se crea el real.
  final ApiService? api;

  /// Acción al tocar la barra. `null` en producción → abre la vista
  /// de planes (`showPremiumUpsellSheet`).
  final VoidCallback? onOpenPlans;

  /// Estado de suscripción inyectado por el padre. Cuando el Dashboard
  /// ya posee el estado (lo carga una sola vez para dimensionar el
  /// header), lo pasa aquí para evitar un segundo fetch a
  /// `/subscription/status`. Si es `null` y [selfLoad] es `true`, la
  /// barra lo carga ella misma (uso standalone / tests).
  final SubscriptionStatus? status;

  /// Si la barra debe cargar el estado por su cuenta cuando [status] es
  /// `null`. El Dashboard lo pone en `false` porque ya inyecta el estado.
  final bool selfLoad;

  @override
  State<TrialBar> createState() => _TrialBarState();
}

class _TrialBarState extends State<TrialBar> {
  late final ApiService _api;

  /// Estado de suscripción cargado. `null` mientras carga o si el
  /// fetch falló — en ambos casos la barra no se muestra.
  SubscriptionStatus? _status;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ApiService(AuthService());
    // Solo carga por su cuenta si nadie le inyectó el estado y está en
    // modo self-load. En el Dashboard el padre inyecta `status`, así que
    // no se dispara un segundo fetch.
    if (widget.status == null && widget.selfLoad) {
      _loadStatus();
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _api.fetchSubscriptionStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } on AppError catch (e) {
      // No tragamos el error: lo registramos. Pero la barra no se
      // muestra para no bloquear el Dashboard (regla de la feature).
      debugPrint('TrialBar: no se pudo cargar /subscription/status: '
          '${e.message}');
    } catch (e) {
      // Cualquier fallo inesperado: igual se registra y la barra
      // queda oculta. Prohibido `catch (_)` que trague el error.
      debugPrint('TrialBar: error inesperado al cargar el estado: $e');
    }
  }

  void _openPlans() {
    if (widget.onOpenPlans != null) {
      widget.onOpenPlans!();
      return;
    }
    showPremiumUpsellSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    // El estado inyectado por el padre tiene prioridad; si no, el que la
    // barra cargó por su cuenta.
    final status = widget.status ?? _status;
    // Mientras carga, falló o el tenant es Pro: no se muestra nada.
    if (status == null) return const SizedBox.shrink();

    if (status.status == SubscriptionStatusValue.trial) {
      return _TrialProgress(status: status, onTap: _openPlans);
    }
    if (status.status == SubscriptionStatusValue.free) {
      return _UpgradePrompt(onTap: _openPlans);
    }
    // PRO_ACTIVE / PRO_PAST_DUE → sin barra ni prompt.
    return const SizedBox.shrink();
  }
}

/// Barra de progreso del trial. Etiqueta + barra de días usados sobre
/// el total. Tappable → abre la vista de planes.
class _TrialProgress extends StatelessWidget {
  const _TrialProgress({required this.status, required this.onTap});

  final SubscriptionStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = status.trialDaysRemaining;
    final dayWord = remaining == 1 ? 'día' : 'días';
    final label = 'Te quedan $remaining $dayWord de prueba Pro';

    return Semantics(
      button: true,
      label: '$label. Toca para ver los planes.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('trial_bar'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fila etiqueta + chevron. Usamos Flexible para que el
                // texto se elida en 360dp en vez de hacer overflow.
                Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded,
                        color: Color(0xFFFBBF24), size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.7)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    key: const Key('trial_bar_progress'),
                    value: status.trialProgress,
                    minHeight: 8,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.22),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFBBF24)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Prompt compacto "Activa Pro" para el tenant cuyo trial venció
/// (estado FREE). Tappable → abre la vista de planes.
class _UpgradePrompt extends StatelessWidget {
  const _UpgradePrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Activa Pro. Toca para ver los planes.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('trial_bar_upgrade'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: Color(0xFFFBBF24), size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Activa Pro y desbloquea todas las herramientas',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: Colors.white.withValues(alpha: 0.8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
