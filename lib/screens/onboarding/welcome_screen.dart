// Spec: specs/037-reel-capacidades-dashboard/spec.md
//
// Welcome / tour educativo post-login. Reemplaza el welcome plano de
// 1 pantalla por un PageView de 6 pasos que explica QUÉ puede hacer
// el dueño en VendIA y CÓMO. Al terminar (o saltar):
//   1. PATCH /store/profile { onboarding_completed: true }
//   2. Marca el flag local en AuthService (offline-safe)
//   3. Llama onCompleted (navega al Dashboard)
//
// Diseño visual coherente con Login / Signup / Dashboard:
// - Gradient azul brand de fondo
// - Header con logo + "Saltar" link blanco + progress bar segmentado
// - Cada paso = hero emoji en círculo + título + texto + bullets
// - Botones nav abajo: Atrás (oculto en step 1) + Siguiente/Empezar
//
// Tests: mantiene las keys públicas `welcome_logo` y
// `welcome_start_button` para no romper la suite existente.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class WelcomeScreen extends StatefulWidget {
  /// Inyección de [ApiService] para tests.
  final ApiService? apiOverride;

  /// Se invoca tras completar el onboarding (navega al Dashboard).
  final VoidCallback? onCompleted;

  const WelcomeScreen({
    super.key,
    this.apiOverride,
    this.onCompleted,
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final ApiService _api;
  late final PageController _pageCtrl;
  int _currentStep = 0;
  bool _submitting = false;

  // ── Contenido del tour ───────────────────────────────────────────
  // Cada step: emoji hero, título, texto principal, bullets opcionales.
  // El copy es español neutral (UI_RULES §11) — modo USTED, sin voseo.
  static const List<_TourStep> _steps = [
    _TourStep(
      emoji: '🏪', // fallback si el asset no carga
      useLogo: true,
      title: '¡Bienvenido a VendIA!',
      body:
          'Su negocio en el bolsillo. Vender, manejar inventario y '
          'ver sus ganancias — todo en un solo lugar.',
      bullets: [],
    ),
    _TourStep(
      emoji: '💰',
      title: 'Registrar ventas',
      body:
          'Cobre rápido eligiendo productos del catálogo o escaneando '
          'el código de barras. Cada venta queda guardada.',
      bullets: [
        ('🧾', 'Efectivo, digital (Nequi/Bre-B) o fiado'),
        ('📷', 'Escanea el código del producto al cobrar'),
        ('🧮', 'Sume cantidades, descuentos e impuestos'),
      ],
    ),
    _TourStep(
      emoji: '📦',
      title: 'Manejar inventario',
      body:
          'Cargue lo que vende a su catálogo. Vea el stock al '
          'instante y reciba avisos cuando algo se está acabando.',
      bullets: [
        ('➕', 'Agregue productos uno por uno o por voz'),
        ('📊', 'Importe un Excel con todos sus productos'),
        ('⚠️', 'Alertas cuando el stock está bajo'),
      ],
    ),
    _TourStep(
      emoji: '📈',
      title: 'Ver sus ganancias',
      body:
          'Cuánto vendió, cuánto ganó y qué productos rinden más. '
          'Todo en pantallas claras, sin números confusos.',
      bullets: [
        ('💵', 'Ventas de hoy y del mes'),
        ('🏆', 'Productos más vendidos y de mayor margen'),
        ('🔍', 'Filtre por sede, empleado o forma de pago'),
      ],
    ),
    _TourStep(
      emoji: '✨',
      title: 'Descubrir más opciones',
      body:
          'En el carrusel arriba del panel verá módulos extra para '
          'su negocio. Active solo los que necesite.',
      bullets: [
        ('👥', 'Mis Clientes — quién le compra y cuánto'),
        ('📋', 'Cotizaciones — propuestas formales por WhatsApp'),
        ('📢', 'Promociones — avise ofertas a sus clientes'),
        ('🍳', 'Recetas, mesas, trabajos y más'),
      ],
    ),
    _TourStep(
      emoji: '✅',
      title: '¡Todo listo!',
      body:
          'Su VendIA está preparado. Si necesita ayuda, en Mi Negocio '
          'encontrará el soporte y los ajustes. ¡A vender!',
      bullets: [],
    ),
  ];

  int get _totalSteps => _steps.length;
  bool get _isLastStep => _currentStep == _totalSteps - 1;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();

    try {
      await _api.updateBusinessProfile({'onboarding_completed': true});
    } catch (_) {
      // Offline / error de red — igual marcamos el flag local para no
      // atrapar al dueño en el tour. El backend reconcilia luego.
    }
    try {
      await AuthService().updateOnboardingCompleted(true);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _submitting = false);
    widget.onCompleted?.call();
  }

  void _goNext() {
    HapticFeedback.lightImpact();
    if (_isLastStep) {
      _completeOnboarding();
      return;
    }
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _goBack() {
    if (_currentStep == 0) return;
    HapticFeedback.lightImpact();
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E3A8A),
              Color(0xFF3B82F6),
              Color(0xFF6366F1),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header: progreso + Saltar ────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: List.generate(_totalSteps, (i) {
                          final active = i <= _currentStep;
                          return Expanded(
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 260),
                              height: 5,
                              margin: EdgeInsets.only(
                                  right: i < _totalSteps - 1 ? 5 : 0),
                              decoration: BoxDecoration(
                                color: active
                                    ? Colors.white
                                    : Colors.white
                                        .withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (!_isLastStep)
                      TextButton(
                        onPressed:
                            _submitting ? null : _completeOnboarding,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                        ),
                        child: Text(
                          'Saltar',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── PageView con los pasos ────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _currentStep = i),
                  itemCount: _totalSteps,
                  itemBuilder: (_, i) {
                    final step = _steps[i];
                    return _TourStepView(
                      step: step,
                      // Mantener la key del logo solo en el step 1 para
                      // que el test de welcome_logo siga funcionando.
                      heroKey: i == 0
                          ? const Key('welcome_logo')
                          : null,
                    );
                  },
                ),
              ),

              // ── Botones de navegación ─────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          height: 60,
                          width: 60,
                          child: OutlinedButton(
                            onPressed: _submitting ? null : _goBack,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white
                                    .withValues(alpha: 0.55),
                                width: 1.5,
                              ),
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: SizedBox(
                        height: 60,
                        child: ElevatedButton(
                          key: const Key('welcome_start_button'),
                          onPressed: _submitting ? null : _goNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E3A8A),
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.55),
                            elevation: 0,
                            shape: const StadiumBorder(),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.6,
                                    color: Color(0xFF1E3A8A),
                                  ),
                                )
                              : Text(
                                  _isLastStep ? 'Empezar' : 'Siguiente',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Estructura inmutable de un paso del tour.
class _TourStep {
  final String emoji;
  final String title;
  final String body;
  /// Bullets opcionales: (emoji corto, texto).
  final List<(String, String)> bullets;
  /// Si es `true`, el hero muestra el logo oficial de VendIA en lugar
  /// del [emoji]. Usado solo en el step de bienvenida.
  final bool useLogo;

  const _TourStep({
    required this.emoji,
    required this.title,
    required this.body,
    required this.bullets,
    this.useLogo = false,
  });
}

/// Render de un paso individual — hero emoji + título + body +
/// bullets opcionales con su propio emoji.
class _TourStepView extends StatelessWidget {
  final _TourStep step;
  final Key? heroKey;

  const _TourStepView({required this.step, this.heroKey});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // ── Hero — logo oficial de VendIA en el step 1; emoji
          // ilustrativo en los pasos siguientes (varía por tema).
          Center(
            child: Container(
              key: heroKey,
              width: 148,
              height: 148,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(-2, -3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: step.useLogo
                  ? ClipOval(
                      child: Image.asset(
                        'assets/images/vendia_icon_1024.png',
                        fit: BoxFit.contain,
                      ),
                    )
                  : Center(
                      child: Text(
                        step.emoji,
                        style: const TextStyle(fontSize: 84, height: 1.0),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 28),

          // ── Título
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // ── Body
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),

          // ── Bullets (opcional) — card glass con la lista
          if (step.bullets.isNotEmpty) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                children: [
                  for (final (icon, text) in step.bullets) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              icon,
                              style:
                                  const TextStyle(fontSize: 22, height: 1.2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              text,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.4,
                                color: Colors.white
                                    .withValues(alpha: 0.95),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
