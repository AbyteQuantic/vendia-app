// Spec: specs/036-dashboard-adaptativo-onboarding/spec.md
// Spec: specs/037-reel-capacidades-dashboard/spec.md
// Spec: specs/106-onboarding-conversacional-agente/spec.md
//
// Compuerta post-login: decide qué pantalla mostrar después de
// autenticarse.
//
//   onboarding_completed == false  → VendiChatScreen (Spec 106 — el
//                                    asistente configura el negocio
//                                    conversando; reemplaza a WelcomeScreen)
//   onboarding_completed == true   → DashboardScreen
//
// Centraliza el check para que login / splash / branch-selector no
// tengan que duplicar la lógica.
//
// Source of truth: el backend (`GET /store/profile.onboarding_completed`).
// El endpoint `/login` NO devuelve este flag — solo `/store/profile` lo
// hace —, así que un re-login no refresca el cache local. Por eso este
// gate fetchea cada vez al backend y usa el cache de AuthService solo
// como fallback offline.

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../dashboard/dashboard_screen.dart';
import 'vendi/vendi_chat_screen.dart';

class PostLoginGate extends StatefulWidget {
  final String ownerName;
  final String businessName;

  /// Solo para tests: fuerza el resultado del check sin tocar red/almacén.
  @visibleForTesting
  final bool? onboardingCompletedOverride;

  const PostLoginGate({
    super.key,
    required this.ownerName,
    required this.businessName,
    this.onboardingCompletedOverride,
  });

  @override
  State<PostLoginGate> createState() => _PostLoginGateState();
}

class _PostLoginGateState extends State<PostLoginGate> {
  /// null mientras se resuelve el flag; true/false una vez resuelto.
  bool? _onboardingCompleted;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    if (widget.onboardingCompletedOverride != null) {
      setState(() => _onboardingCompleted = widget.onboardingCompletedOverride);
      return;
    }
    final auth = AuthService();
    bool completed = true;

    // 1) Source of truth = backend. Lo consultamos cada vez que se
    //    monta el gate (post-login, post-splash, post-branch-select)
    //    para no quedar atrapados en un cache que no se invalida
    //    por logout (el endpoint /login no devuelve este flag, así
    //    que reloguear no refresca el cache local — esta consulta sí).
    try {
      final api = ApiService(auth);
      final profile = await api.fetchBusinessProfile();
      if (profile.containsKey('onboarding_completed')) {
        completed = profile['onboarding_completed'] == true;
        // Sincronizar cache local para que offline siga funcionando.
        await auth.updateOnboardingCompleted(completed);
      } else {
        // El backend no expuso el flag (versión vieja del backend);
        // caemos al cache.
        completed = await auth.getOnboardingCompleted();
      }
    } catch (_) {
      // 2) Offline o error de red — caemos al cache. Fail-open: ante
      //    cualquier error mostramos el Dashboard, nunca atrapamos
      //    al dueño en la welcome por una lectura fallida.
      try {
        completed = await auth.getOnboardingCompleted();
      } catch (_) {
        completed = true;
      }
    }

    if (!mounted) return;
    setState(() {
      _onboardingCompleted = completed;
    });
  }

  void _goToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          ownerName: widget.ownerName,
          businessName: widget.businessName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _onboardingCompleted;
    if (resolved == null) {
      // Carga breve (lee un flag local). Sin spinner: pantalla blanca para una
      // transición limpia desde el splash (no mostrar el loader genérico).
      return const Scaffold(backgroundColor: Colors.white, body: SizedBox.shrink());
    }

    if (!resolved) {
      // Primer ingreso — Vendi configura el negocio conversando (Spec 106,
      // AC-01). Al confirmar la propuesta navegamos al Dashboard.
      return VendiChatScreen(onCompleted: _goToDashboard);
    }

    return DashboardScreen(
      ownerName: widget.ownerName,
      businessName: widget.businessName,
    );
  }
}
