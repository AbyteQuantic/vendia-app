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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/voice_recorder.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';
import '../post_login_gate.dart';
import 'onboarding_cards.dart';

/// Test seams para el dictado por voz (mismos que VoiceInventoryScreen).
typedef ResolvePath = Future<String> Function();
typedef ReadAudio = Future<RecordedAudio> Function(String stopResult);

/// Fondo premium del onboarding (blanco casi puro cálido — Spec 045 §5).
const Color kAgenticBg = Color(0xFFFDFDFD);
const Color kAgenticPurple = Color(0xFF6366F1);

class OnboardingAgenticView extends StatefulWidget {
  const OnboardingAgenticView({
    super.key,
    this.apiOverride,
    this.recorderOverride,
    this.resolvePathOverride,
    this.readAudioOverride,
    this.persistOverride = true,
  });

  /// Inyectable para tests; en producción usa el ApiService default.
  final ApiService? apiOverride;

  /// Test seams del dictado por voz (en producción usan el AudioRecorder real
  /// + los helpers web-safe de voice_recorder.dart).
  final AudioRecorder? recorderOverride;
  final ResolvePath? resolvePathOverride;
  final ReadAudio? readAudioOverride;

  /// Desactiva la persistencia en SharedPreferences (tests).
  final bool persistOverride;

  @override
  State<OnboardingAgenticView> createState() => _OnboardingAgenticViewState();
}

class _OnboardingAgenticViewState extends State<OnboardingAgenticView> {
  late final OnboardingStepperController _ctrl;
  late final ApiService _api = widget.apiOverride ?? ApiService(AuthService());
  late final AudioRecorder _recorder =
      widget.recorderOverride ?? AudioRecorder();
  late final ResolvePath _resolvePath =
      widget.resolvePathOverride ?? recordingPath;
  late final ReadAudio _readAudio =
      widget.readAudioOverride ?? readRecordedAudio;
  final _inputCtrl = TextEditingController();

  static const String _prefsKey = 'vendia:onboarding:current';

  bool _parsing = false;
  bool _recording = false; // dictado por voz en curso
  bool _degraded = false; // la IA no está disponible → banner discreto
  String? _clarifyPrompt;
  // Campos recién reconocidos por la IA → pulso sutil en su card.
  Set<String> _justFilled = {};
  Timer? _pulseTimer;
  Timer? _persistTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = context.read<OnboardingStepperController>();
    _ctrl.addListener(_onControllerChange);
    _restore();
  }

  void _onControllerChange() {
    if (!mounted) return;
    if (_ctrl.status == StepperStatus.success) {
      _clearPersisted();
      _finishOnboarding();
      return;
    }
    _schedulePersist();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _persistTimer?.cancel();
    _ctrl.removeListener(_onControllerChange);
    _recorder.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  // ── Persistencia (sobrevive un refresh en web; Isar es stub) ──────────────
  // PIN/confirmPin NUNCA se persisten (dato sensible) — el tendero los reteclea.
  Map<String, dynamic> get _persistable => {
        'owner_name': _ctrl.ownerName,
        'owner_last_name': _ctrl.ownerLastName,
        'phone': _ctrl.phone,
        'business_name': _ctrl.businessName,
        'razon_social': _ctrl.razonSocial,
        'nit': _ctrl.nit,
        'address': _ctrl.address,
        'business_type': _ctrl.businessType,
        'has_multiple_branches': _ctrl.hasMultipleBranches,
        'offers_services': _ctrl.offersServices,
        'sells_by_weight': _ctrl.sellsByWeight,
        'has_tables': _ctrl.hasTables,
        'has_employees': _ctrl.hasEmployees,
        'logo_url': _ctrl.logoUrl,
      };

  void _schedulePersist() {
    if (!widget.persistOverride) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_persistable));
      } catch (_) {/* persistencia best-effort */}
    });
  }

  Future<void> _clearPersisted() async {
    if (!widget.persistOverride) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  Future<void> _restore() async {
    if (!widget.persistOverride) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      String s(String k) => (m[k] as String?) ?? '';
      if (s('owner_name').isNotEmpty) _ctrl.ownerName = s('owner_name');
      if (s('owner_last_name').isNotEmpty) {
        _ctrl.ownerLastName = s('owner_last_name');
      }
      if (s('phone').isNotEmpty) _ctrl.phone = s('phone');
      if (s('business_name').isNotEmpty) _ctrl.businessName = s('business_name');
      if (s('razon_social').isNotEmpty) _ctrl.razonSocial = s('razon_social');
      if (s('nit').isNotEmpty) _ctrl.nit = s('nit');
      if (s('address').isNotEmpty) _ctrl.address = s('address');
      final bt = s('business_type');
      if (OnboardingStepperController.validBusinessTypes.contains(bt)) {
        _ctrl.setPrimaryBusinessType(bt);
      }
      if (m['has_multiple_branches'] is bool) {
        _ctrl.hasMultipleBranches = m['has_multiple_branches'] as bool;
      }
      if (m['offers_services'] is bool) {
        _ctrl.offersServices = m['offers_services'] as bool;
      }
      if (m['sells_by_weight'] is bool) {
        _ctrl.sellsByWeight = m['sells_by_weight'] as bool;
      }
      if (m['has_tables'] is bool) _ctrl.hasTables = m['has_tables'] as bool;
      if (m['has_employees'] is bool) {
        _ctrl.hasEmployees = m['has_employees'] as bool;
      }
      if (s('logo_url').isNotEmpty) _ctrl.setLogoUrl(s('logo_url'));
      if (mounted) setState(() {});
    } catch (_) {/* restauración best-effort */}
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

  Future<void> _sendText() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _parsing) return;
    FocusScope.of(context).unfocus();
    await _runParse(text: text);
  }

  /// Camino común de extracción: texto y/o audio → parseOnboarding →
  /// applyParseResult. La IA nunca bloquea: ante degraded, banner discreto.
  Future<void> _runParse({String text = '', RecordedAudio? audio}) async {
    if (_parsing) return;
    setState(() => _parsing = true);
    final before = _snapshotFields();
    try {
      final result = await _api.parseOnboarding(
        text: text,
        audioBytes: audio?.bytes,
        mimeType: audio?.mimeType ?? 'audio/webm',
        filename: audio?.filename ?? 'onboarding.webm',
        current: _current,
      );
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

  // ── Dictado por voz (reusa voice_recorder web-safe, como F020) ────────────
  Future<void> _toggleMic() async {
    if (_parsing) return;
    if (_recording) {
      await _stopAndSendVoice();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    try {
      if (!await _recorder.hasPermission()) {
        _micError('Sin permiso para usar el micrófono. '
            'Actívelo en los ajustes del navegador o del teléfono.');
        return;
      }
      final path = await _resolvePath();
      final config = await resolveRecordConfig(_recorder);
      await _recorder.start(config, path: path);
      if (!mounted) return;
      setState(() => _recording = true);
    } catch (_) {
      if (mounted) setState(() => _recording = false);
      _micError('No pudimos iniciar la grabación. '
          'Revise el permiso del micrófono e intente otra vez.');
    }
  }

  Future<void> _stopAndSendVoice() async {
    setState(() => _recording = false);
    String? stopResult;
    try {
      stopResult = await _recorder.stop();
    } catch (_) {
      stopResult = null;
    }
    if (stopResult == null) {
      _micError('No se pudo guardar el audio. Intente otra vez.');
      return;
    }
    RecordedAudio audio;
    try {
      audio = await _readAudio(stopResult);
    } catch (_) {
      unawaited(disposeRecordedAudio(stopResult));
      _micError('No se pudo leer el audio grabado. Intente otra vez.');
      return;
    }
    await _runParse(audio: audio);
    unawaited(disposeRecordedAudio(stopResult));
  }

  void _micError(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m, style: const TextStyle(fontSize: 15)),
      backgroundColor: AppTheme.error,
    ));
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
              recording: _recording,
              onSend: _sendText,
              onMic: _toggleMic,
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
    required this.recording,
    required this.onSend,
    required this.onMic,
  });
  final TextEditingController controller;
  final bool parsing;
  final bool recording;
  final VoidCallback onSend;
  final VoidCallback onMic;

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
            // Micrófono (dictado) — mismo peso visual que el sparkle. En
            // grabación se pinta rojo para que el tendero sepa que escucha.
            _circleButton(
              key: const Key('agentic_mic'),
              icon: recording ? Icons.stop_rounded : Icons.mic_none_rounded,
              filled: recording,
              filledColor: recording ? AppTheme.error : null,
              onTap: onMic,
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
    Color? filledColor,
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
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: filledColor,
                    gradient: filledColor == null
                        ? const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryLight],
                          )
                        : null,
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
