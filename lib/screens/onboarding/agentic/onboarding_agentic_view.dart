// Spec: specs/045-onboarding-agentic/onboarding_agentic_spec.md
//
// Agentic UI del onboarding (premium tipo Copilot, adaptada al tendero 50+).
// El héroe estético es el input flotante con sparkle + voz, pero el camino
// primario es VOZ + CHIPS + Smart Cards tocables. La IA es un acelerador
// OPCIONAL: si falla, todo se llena a mano (degradación elegante, Art. I + II).
//
// Reusa el OnboardingStepperController existente (mismo _buildPayload, mismo
// submit) — este archivo es 100% capa de presentación.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';
import '../post_login_gate.dart';
import 'onboarding_cards.dart';

/// Fondo premium del onboarding (blanco casi puro cálido — Spec 045 §5).
const Color kAgenticBg = Color(0xFFFDFDFD);
const Color kAgenticPurple = Color(0xFF6366F1);

class OnboardingAgenticView extends StatefulWidget {
  const OnboardingAgenticView({super.key, this.apiOverride});

  /// Inyectable para tests; en producción usa el ApiService default.
  final ApiService? apiOverride;

  @override
  State<OnboardingAgenticView> createState() => _OnboardingAgenticViewState();
}

class _OnboardingAgenticViewState extends State<OnboardingAgenticView> {
  late final OnboardingStepperController _ctrl;
  late final ApiService _api = widget.apiOverride ?? ApiService(AuthService());
  final _inputCtrl = TextEditingController();

  bool _parsing = false;
  bool _degraded = false; // la IA no está disponible → banner discreto
  String? _clarifyPrompt;
  // Campos recién reconocidos por la IA → pulso sutil en su card.
  Set<String> _justFilled = {};
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = context.read<OnboardingStepperController>();
    _ctrl.addListener(_onControllerChange);
  }

  void _onControllerChange() {
    if (!mounted) return;
    if (_ctrl.status == StepperStatus.success) _finishOnboarding();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _ctrl.removeListener(_onControllerChange);
    _inputCtrl.dispose();
    super.dispose();
  }

  void _finishOnboarding() {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, a, __) => PostLoginGate(
          ownerName: '${_ctrl.ownerName} ${_ctrl.ownerLastName}'.trim(),
          businessName: _ctrl.businessName,
        ),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
      (_) => false,
    );
  }

  /// Snapshot del estado capturado para la extracción incremental (D7).
  Map<String, dynamic> get _current => {
        if (_ctrl.ownerName.isNotEmpty) 'owner_name': _ctrl.ownerName,
        if (_ctrl.ownerLastName.isNotEmpty)
          'owner_last_name': _ctrl.ownerLastName,
        if (_ctrl.phone.isNotEmpty) 'phone': _ctrl.phone,
        if (_ctrl.businessName.isNotEmpty) 'business_name': _ctrl.businessName,
        if (_ctrl.address.isNotEmpty) 'address': _ctrl.address,
        if (_ctrl.businessType.isNotEmpty) 'business_type': _ctrl.businessType,
      };

  Future<void> _sendToAI() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _parsing) return;
    FocusScope.of(context).unfocus();
    setState(() => _parsing = true);
    final before = _snapshotFields();
    try {
      final result = await _api.parseOnboarding(text: text, current: _current);
      if (!mounted) return;
      final degraded = result['degraded'] == true;
      if (!degraded) {
        _ctrl.applyParseResult(result);
        _inputCtrl.clear();
      }
      setState(() {
        _degraded = degraded;
        _clarifyPrompt = result['clarify_prompt'] as String?;
        _justFilled = _changedFields(before);
      });
      _schedulePulseClear();
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  void _schedulePulseClear() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _justFilled = {});
    });
  }

  Map<String, String> _snapshotFields() => {
        'sus_datos': _ctrl.ownerName + _ctrl.phone + _ctrl.pin,
        'negocio': _ctrl.businessName + _ctrl.address,
        'local': _ctrl.hasMultipleBranches.toString(),
        'tipo': _ctrl.businessType,
        'logo': _ctrl.logoUrl,
        'empleados': _ctrl.hasEmployees.toString(),
      };

  Set<String> _changedFields(Map<String, String> before) {
    final now = _snapshotFields();
    return now.entries
        .where((e) => before[e.key] != e.value)
        .map((e) => e.key)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    // Reconstruye en cada notifyListeners del controller (canRegister vivo).
    context.watch<OnboardingStepperController>();
    return Scaffold(
      backgroundColor: kAgenticBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _GlassHeader(),
            if (_degraded) const _DegradedBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  const _Greeting(),
                  const SizedBox(height: 20),
                  ...OnboardingCards.all(_ctrl).map(
                    (spec) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SmartCard(
                        spec: spec,
                        pulsing: _justFilled.contains(spec.id),
                        onEdit: () => spec.openEditor(context, _ctrl, _api),
                      ),
                    ),
                  ),
                  if (_clarifyPrompt != null) ...[
                    const SizedBox(height: 4),
                    _ClarifyBubble(text: _clarifyPrompt!),
                  ],
                  const SizedBox(height: 16),
                  _CreateButton(
                    enabled: _ctrl.canRegister &&
                        _ctrl.status != StepperStatus.loading,
                    loading: _ctrl.status == StepperStatus.loading,
                    onTap: () => _ctrl.submitWithCaptcha(null),
                  ),
                  if (_ctrl.status == StepperStatus.error)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _ctrl.errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppTheme.error, fontSize: 15),
                      ),
                    ),
                ],
              ),
            ),
            _FloatingInput(
              controller: _inputCtrl,
              parsing: _parsing,
              onSend: _sendToAI,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Header glassmorphism delgado (reemplaza el gradiente azul sólido) ───────
class _GlassHeader extends StatelessWidget {
  const _GlassHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(
              color: AppTheme.borderColor.withValues(alpha: 0.4), width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryLight],
              ),
            ),
            child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Creemos su negocio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Ya tengo cuenta',
                style: TextStyle(fontSize: 14, color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vamos a crear su negocio',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Cuéntenos por voz, escriba, o toque las tarjetas.',
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _DegradedBanner extends StatelessWidget {
  const _DegradedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.warning.withValues(alpha: 0.10),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: const Text(
        'Sin conexión con la IA — toque cada tarjeta para llenarla.',
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
      ),
    );
  }
}

class _ClarifyBubble extends StatelessWidget {
  const _ClarifyBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kAgenticPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAgenticPurple.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: kAgenticPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 15, color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({
    required this.enabled,
    required this.loading,
    required this.onTap,
  });
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ElevatedButton(
        key: const Key('agentic_create_account'),
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.35),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: loading
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: Colors.white),
              )
            : const Text(
                'Crear mi cuenta',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
      ),
    );
  }
}

// ─── Floating Input Field premium (sparkle + voz) ────────────────────────────
class _FloatingInput extends StatelessWidget {
  const _FloatingInput({
    required this.controller,
    required this.parsing,
    required this.onSend,
  });
  final TextEditingController controller;
  final bool parsing;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: AppTheme.borderColor.withValues(alpha: 0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            // Micrófono (dictado) — mismo peso visual que el sparkle.
            _circleButton(
              key: const Key('agentic_mic'),
              icon: Icons.mic_none_rounded,
              filled: false,
              onTap: () {
                HapticFeedback.lightImpact();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Dictado por voz: próximamente. '
                      'Por ahora escriba o toque las tarjetas.'),
                ));
              },
            ),
            Expanded(
              child: TextField(
                key: const Key('agentic_input'),
                controller: controller,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(
                    fontSize: 16, color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText:
                      'Escriba o dicte… ej: Tienda Doña Marta, abarrotes',
                  hintStyle: TextStyle(fontSize: 15),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            _circleButton(
              key: const Key('agentic_send'),
              icon: Icons.auto_awesome,
              filled: true,
              loading: parsing,
              onTap: onSend,
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required Key key,
    required IconData icon,
    required bool filled,
    bool loading = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          key: key,
          color: filled ? null : Colors.transparent,
          shape: const CircleBorder(),
          child: Ink(
            decoration: filled
                ? const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryLight],
                    ),
                  )
                : const BoxDecoration(shape: BoxShape.circle),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: loading ? null : onTap,
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Icon(icon,
                      size: 22,
                      color: filled ? Colors.white : AppTheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
