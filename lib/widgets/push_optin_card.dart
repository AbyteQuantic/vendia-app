// Spec: specs/038-push-notifications-web-android/spec.md
//
// PushOptinCard — Tarjeta que pide al tendero activar las
// notificaciones. Vive en el Dashboard del POS y se muestra SOLO si:
//
//   1. El servicio push está disponible (Firebase configurado +
//      browser/OS soporta).
//   2. El usuario aún no registró ningún token (lista vacía).
//   3. El usuario no rechazó previamente el permiso del browser
//      (en web, se detecta con `Notification.permission == 'denied'`;
//      en móvil con la API de FirebaseMessaging).
//
// El botón "Activar notificaciones" es lo que dispara el prompt
// nativo — el tendero ya sabe qué va a recibir antes de aceptar
// (Art. I: cero fricción cognitiva, AC-01).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/push_service.dart';

/// Wrapper que decide si renderear `PushOptinCard` o no.
/// Se muestra SOLO si:
///   - PushService está disponible (Firebase configurado + browser soporta).
///   - El usuario aún no tiene ningún dispositivo activo registrado.
/// En cualquier otro caso queda invisible — el render es 0px de alto.
///
/// Diseñado para insertarse directo en el Dashboard sin pollear estado
/// global: él mismo consulta `listMyDevices` al montar.
class PushOptinGate extends StatefulWidget {
  const PushOptinGate({super.key});

  @override
  State<PushOptinGate> createState() => _PushOptinGateState();
}

class _PushOptinGateState extends State<PushOptinGate> {
  bool? _shouldShow;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (!PushService().isAvailable) {
      if (mounted) setState(() => _shouldShow = false);
      return;
    }
    try {
      final devices = await PushService().listMyDevices();
      if (!mounted) return;
      setState(() => _shouldShow = devices.isEmpty);
    } catch (_) {
      // Si no podemos consultar (sin sesión, sin red), mejor no
      // ofrecer la tarjeta — evita spam si el backend está caído.
      if (mounted) setState(() => _shouldShow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldShow != true) return const SizedBox.shrink();
    return PushOptinCard(
      onActivated: () => setState(() => _shouldShow = false),
    );
  }
}

class PushOptinCard extends StatefulWidget {
  /// Se llama cuando el tendero activa exitosamente las notificaciones.
  /// El Dashboard lo usa para esconder la tarjeta sin tener que
  /// pollear el estado.
  final VoidCallback? onActivated;

  const PushOptinCard({super.key, this.onActivated});

  @override
  State<PushOptinCard> createState() => _PushOptinCardState();
}

class _PushOptinCardState extends State<PushOptinCard> {
  bool _loading = false;
  String? _error;

  Future<void> _onActivate() async {
    HapticFeedback.lightImpact();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await PushService().requestOptInAndRegister();
      if (!mounted) return;
      if (ok) {
        widget.onActivated?.call();
      } else {
        setState(() {
          _error =
              'Las notificaciones no se pudieron activar. Puede '
              'permitirlas manualmente desde la configuración del '
              'navegador y volver a intentar.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Ocurrió un problema. Vuelva a intentar en un momento.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6D28D9), Color(0xFF4F46E5)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6D28D9).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.notifications_active,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Active las notificaciones',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Le avisamos al instante cuando llegue un pedido nuevo, '
            'un cliente abone un fiado, o tenga un producto a punto '
            'de agotarse — sin tener que abrir la app a cada rato.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _onActivate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF6D28D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Color(0xFF6D28D9),
                      ),
                    )
                  : const Icon(Icons.check_circle, size: 22),
              label: Text(
                _loading ? 'Activando…' : 'Activar notificaciones',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Si tiene iPhone, primero agregue VendIA a la pantalla '
            'de inicio para recibir notificaciones.',
            style: TextStyle(
              color: Color(0xFFE0E7FF),
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
