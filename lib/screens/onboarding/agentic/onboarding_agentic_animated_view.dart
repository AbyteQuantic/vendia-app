// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
//
// Single-View Agentic Onboarding (animado). Orquesta el flujo de preguntas
// (una a la vez + skip), la pila LIFO de undo y las animaciones del Top Canvas,
// delegando en PreviewCanvasWidget + GlassChatConsoleWidget. Reusa el
// OnboardingStepperController (estado/submit), la IA (parseOnboarding), la voz
// y la persistencia. 100% presentación.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/api_service.dart';
import '../../../services/app_error.dart';
import '../../../services/auth_service.dart';
import '../../../services/voice_recorder.dart';
import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';
import '../post_login_gate.dart';
import '../vendi/vendi_orb.dart';
import '../../legal/terms_screen.dart';
import 'glass_chat_console_widget.dart';
import 'onboarding_animation_controller.dart';
import 'onboarding_flow.dart';

typedef ResolvePath = Future<String> Function();
typedef ReadAudio = Future<RecordedAudio> Function(String stopResult);

class OnboardingAgenticAnimatedView extends StatefulWidget {
  const OnboardingAgenticAnimatedView({
    super.key,
    this.apiOverride,
    this.recorderOverride,
    this.resolvePathOverride,
    this.readAudioOverride,
    this.persistOverride = true,
  });

  final ApiService? apiOverride;
  final AudioRecorder? recorderOverride;
  final ResolvePath? resolvePathOverride;
  final ReadAudio? readAudioOverride;
  final bool persistOverride;

  @override
  State<OnboardingAgenticAnimatedView> createState() =>
      _OnboardingAgenticAnimatedViewState();
}

class _OnboardingAgenticAnimatedViewState
    extends State<OnboardingAgenticAnimatedView>
    with TickerProviderStateMixin {
  late final OnboardingStepperController _ctrl;
  late final OnboardingAnimationController _anim;
  late final ApiService _api = widget.apiOverride ?? ApiService(AuthService());
  late final AudioRecorder _recorder =
      widget.recorderOverride ?? AudioRecorder();
  late final ResolvePath _resolvePath =
      widget.resolvePathOverride ?? recordingPath;
  late final ReadAudio _readAudio =
      widget.readAudioOverride ?? readRecordedAudio;
  final _inputCtrl = TextEditingController();

  static const String _prefsKey = 'vendia:onboarding:current';

  int _qIndex = 0;
  final List<String> _trail = []; // ids contestados, en orden (LIFO)
  final Set<String> _answered = {}; // respuestas explícitas (chips sí/no)

  bool _parsing = false;
  bool _recording = false;
  bool _degraded = false;
  // OS1: saludo de Vendi (palomilla) antes de la primera pregunta. Se salta
  // automáticamente si hay datos restaurados de una sesión anterior.
  bool _showGreeting = true;
  Timer? _persistTimer;
  bool _animReady = false;

  // Señales para la velocidad del video de fondo (Spec 048).
  bool _typing = false; // el usuario está escribiendo
  Timer? _typingTimer;
  bool _persisting = false; // guardando el dato en SharedPreferences

  @override
  void initState() {
    super.initState();
    _ctrl = context.read<OnboardingStepperController>();
    _anim = OnboardingAnimationController(vsync: this);
    _animReady = true;
    _ctrl.addListener(_onControllerChange);
    _inputCtrl.addListener(_onInput);
    _restore();
  }

  /// El usuario escribe → tempo lento. El flag se apaga 1.2s después de la
  /// última tecla (volvemos a "esperando input").
  void _onInput() {
    _typingTimer?.cancel();
    if (!_typing && mounted) setState(() => _typing = true);
    _typingTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _typing = false);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion no se re-aplica en caliente; el value=1.0 ya cubre el caso.
  }

  void _onControllerChange() {
    if (!mounted) return;
    if (_ctrl.status == StepperStatus.success) {
      _clearPersisted();
      _disposeAnimSafely();
      _finishOnboarding();
      return;
    }
    if (_animReady) {
      _anim.reflect(
          hasType: _ctrl.businessTypeSelected, hasLogo: _ctrl.logoSelected);
    }
    _schedulePersist();
  }

  void _disposeAnimSafely() {
    if (_animReady) {
      _animReady = false;
      _anim.dispose();
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _typingTimer?.cancel();
    _ctrl.removeListener(_onControllerChange);
    _inputCtrl.removeListener(_onInput);
    _disposeAnimSafely();
    _recorder.dispose();
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

  OnboardingQuestion get _question => kOnboardingQuestions[_qIndex];

  // ── Avance / retroceso (LIFO) ─────────────────────────────────────────────
  void _recomputeTrailAndIndex() {
    final next = firstUnansweredIndex(_ctrl, _answered);
    for (var i = 0; i < next; i++) {
      final id = kOnboardingQuestions[i].id;
      if (kOnboardingQuestions[i].isResolved(_ctrl, _answered) &&
          !_trail.contains(id)) {
        _trail.add(id);
      }
    }
    _qIndex = next;
  }

  void _advance() {
    final before = _qIndex;
    _recomputeTrailAndIndex();
    if (_qIndex != before) _anim.enterStep();
    setState(() {});
  }

  void _back() {
    if (_trail.isEmpty) return;
    HapticFeedback.selectionClick();
    final id = _trail.removeLast();
    questionById(id).reset(_ctrl, _answered);
    _anim.reverseStep();
    setState(() {
      _qIndex = kOnboardingQuestions.indexWhere((q) => q.id == id);
    });
  }

  /// ¿Hay algo que valga la pena descartar? (oculta el botón en el arranque
  /// limpio para no añadir ruido cuando no hay nada que limpiar).
  bool get _hasAnyData =>
      _ctrl.ownerName.isNotEmpty ||
      _ctrl.ownerLastName.isNotEmpty ||
      _ctrl.phone.isNotEmpty ||
      _ctrl.businessName.isNotEmpty ||
      _ctrl.address.isNotEmpty ||
      _ctrl.businessTypeSelected ||
      _ctrl.logoSelected ||
      _answered.isNotEmpty ||
      _trail.isNotEmpty;

  /// "Empezar de nuevo" — borra la persistencia y resetea TODO el estado
  /// (controlador + navegación) para descartar datos de una sesión anterior.
  Future<void> _confirmReset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Empezar de nuevo?'),
        content: const Text(
            'Se borrarán los datos que ingresó hasta ahora. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Empezar de nuevo', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    if (yes == true) await _resetAll();
  }

  Future<void> _resetAll() async {
    await _clearPersisted();
    _ctrl.reset();
    _answered.clear();
    _trail.clear();
    _inputCtrl.clear();
    if (!mounted) return;
    setState(() {
      _qIndex = 0;
      _degraded = false;
    });
    if (_animReady) _anim.reflect(hasType: false, hasLogo: false);
    HapticFeedback.selectionClick();
  }

  void _onAdvanceText() {
    if (_question.isResolved(_ctrl, _answered)) {
      FocusScope.of(context).unfocus();
      _advance();
    } else {
      _hint('Complete este dato para continuar.');
    }
  }

  Future<void> _onChip(String questionId, String value) async {
    switch (questionId) {
      case 'tipo':
        _ctrl.setPrimaryBusinessType(value);
        break;
      case 'local':
        _ctrl.setMultipleBranches(value == 'varios');
        _answered.add('local');
        break;
      case 'empleados':
        _ctrl.setHasEmployees(value == 'si');
        _answered.add('empleados');
        break;
      case 'logo':
        await _handleLogo(value);
        return; // _handleLogo llama _advance al terminar
    }
    _advance();
  }

  Future<void> _handleLogo(String intent) async {
    try {
      if (intent == 'generar') {
        if (_ctrl.businessName.trim().isEmpty || !_ctrl.businessTypeSelected) {
          _hint('Primero complete el nombre y el tipo de su negocio.');
          return;
        }
        _setBusy(true);
        final res = await _api.previewLogoIA(
          businessName: _ctrl.businessName,
          businessType: _ctrl.businessType,
          details: _ctrl.businessName,
        );
        final url = (res['logo_url'] as String?)?.trim() ?? '';
        if (url.isNotEmpty) _ctrl.setLogoUrl(url);
      } else if (intent == 'subir') {
        final picked = await ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 90,
            maxWidth: 1024,
            maxHeight: 1024);
        if (picked == null) return;
        _setBusy(true);
        final res = await _api.previewLogoUpload(picked);
        final url = (res['logo_url'] as String?)?.trim() ?? '';
        if (url.isNotEmpty) _ctrl.setLogoUrl(url);
      }
    } on AppError catch (e) {
      _hint(e.message);
    } catch (_) {
      _hint('No pudimos preparar el logo. Intente de nuevo.');
    } finally {
      _setBusy(false);
    }
    if (_ctrl.logoSelected) _advance();
  }

  void _setBusy(bool v) {
    if (mounted) setState(() => _parsing = v);
  }

  // ── IA (texto/voz) ────────────────────────────────────────────────────────
  Map<String, dynamic> get _current => {
        if (_ctrl.ownerName.isNotEmpty) 'owner_name': _ctrl.ownerName,
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

  Future<void> _runParse({String text = '', RecordedAudio? audio}) async {
    if (_parsing) return;
    setState(() => _parsing = true);
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
      setState(() => _degraded = degraded);
      _advance();
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

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
      if (!await _recorder.hasPermission()) {
        _hint('Sin permiso para usar el micrófono.');
        return;
      }
      final path = await _resolvePath();
      final config = await resolveRecordConfig(_recorder);
      await _recorder.start(config, path: path);
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      if (mounted) setState(() => _recording = false);
      _hint('No pudimos iniciar la grabación.');
    }
  }

  Future<void> _stopAndSendVoice() async {
    setState(() => _recording = false);
    String? stop;
    try {
      stop = await _recorder.stop();
    } catch (_) {
      stop = null;
    }
    if (stop == null) {
      _hint('No se pudo guardar el audio.');
      return;
    }
    try {
      final audio = await _readAudio(stop);
      await _runParse(audio: audio);
    } catch (_) {
      _hint('No se pudo leer el audio.');
    } finally {
      unawaited(disposeRecordedAudio(stop));
    }
  }

  void _hint(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m, style: const TextStyle(fontSize: 15))));
  }

  // ── Persistencia (PIN nunca) ──────────────────────────────────────────────
  Map<String, dynamic> get _persistable => {
        'owner_name': _ctrl.ownerName,
        'owner_last_name': _ctrl.ownerLastName,
        'phone': _ctrl.phone,
        'business_name': _ctrl.businessName,
        'address': _ctrl.address,
        'business_type': _ctrl.businessType,
        'has_multiple_branches': _ctrl.hasMultipleBranches,
        'has_employees': _ctrl.hasEmployees,
        'logo_url': _ctrl.logoUrl,
        'answered': _answered.toList(),
      };

  void _schedulePersist() {
    if (!widget.persistOverride) return;
    _persistTimer?.cancel();
    // "Guardando" → el fondo se acelera un poco mientras se persiste.
    if (mounted && !_persisting) setState(() => _persisting = true);
    _persistTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_persistable));
      } catch (_) {}
      if (mounted) setState(() => _persisting = false);
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
    if (!widget.persistOverride) {
      setState(() {
        _recomputeTrailAndIndex();
        if (_hasAnyData) _showGreeting = false;
      });
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        String s(String k) => (m[k] as String?) ?? '';
        if (s('owner_name').isNotEmpty) _ctrl.ownerName = s('owner_name');
        if (s('owner_last_name').isNotEmpty) {
          _ctrl.ownerLastName = s('owner_last_name');
        }
        if (s('phone').isNotEmpty) _ctrl.phone = s('phone');
        if (s('business_name').isNotEmpty) {
          _ctrl.businessName = s('business_name');
        }
        if (s('address').isNotEmpty) _ctrl.address = s('address');
        final bt = s('business_type');
        if (OnboardingStepperController.validBusinessTypes.contains(bt)) {
          _ctrl.setPrimaryBusinessType(bt);
        }
        if (m['has_multiple_branches'] is bool) {
          _ctrl.hasMultipleBranches = m['has_multiple_branches'] as bool;
        }
        if (m['has_employees'] is bool) {
          _ctrl.hasEmployees = m['has_employees'] as bool;
        }
        if (s('logo_url').isNotEmpty) _ctrl.setLogoUrl(s('logo_url'));
        for (final a in (m['answered'] as List? ?? const [])) {
          _answered.add(a.toString());
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _recomputeTrailAndIndex();
        if (_hasAnyData) _showGreeting = false;
      });
      if (_animReady) {
        _anim.reflect(
            hasType: _ctrl.businessTypeSelected, hasLogo: _ctrl.logoSelected);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<OnboardingStepperController>();
    final compact = MediaQuery.of(context).viewInsets.bottom > 0;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion && _animReady) {
      _anim.reflect(
          hasType: _ctrl.businessTypeSelected, hasLogo: _ctrl.logoSelected);
    }

    // Spec 106 Adenda OS1 ("Her"): fondo limpio en la gama clara de la marca,
    // el símbolo vivo de Vendi como protagonista y la pregunta debajo.
    final busy =
        _parsing || _ctrl.status == StepperStatus.loading || _persisting;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF7FBFD), Color(0xFFEAF4FA)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _header(),
              if (_degraded) _degradedBanner(),
              Expanded(
                child: Center(
                  child: VendiOrb(
                    key: const Key('vendi_orb'),
                    shape: _orbShape,
                    size: compact ? 120 : 190,
                    listening: _typing || busy || _recording,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.62),
                child: _showGreeting
                    ? _greetingConsole()
                    : (_ctrl.canRegister
                        ? _readyConsole()
                        : _questionConsole()),
              ),
              _loaderDashes(),
            ],
          ),
        ),
      ),
    );
  }

  /// El símbolo se transforma con cada pregunta (dirección OS1 aprobada):
  /// silueta al preguntar el nombre, teléfono, candado para la clave y la
  /// tienda cuando todo está listo para crear la cuenta.
  VendiOrbShape get _orbShape {
    if (_showGreeting) return VendiOrbShape.palomilla;
    if (_ctrl.canRegister) return VendiOrbShape.store;
    switch (_question.id) {
      case 'owner':
        return VendiOrbShape.user;
      case 'phone':
        return VendiOrbShape.phone;
      case 'pin':
        return VendiOrbShape.lock;
      default:
        return VendiOrbShape.palomilla;
    }
  }

  Widget _header() {
    final canBack = _trail.isNotEmpty;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (canBack)
            TextButton.icon(
              key: const Key('agentic_back'),
              onPressed: _back,
              style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              label: const Text('Atrás', style: TextStyle(fontSize: 15)),
            )
          else
            const SizedBox(width: 12),
          const Spacer(),
          // OS1: el progreso vive en los guiones del loader (abajo), no en
          // un texto 'Paso X de Y'.
          if (_hasAnyData)
            IconButton(
              key: const Key('agentic_reset'),
              onPressed: _confirmReset,
              tooltip: 'Empezar de nuevo',
              visualDensity: VisualDensity.compact,
              color: AppTheme.textSecondary,
              icon: const Icon(Icons.refresh_rounded, size: 22),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _degradedBanner() => Container(
        width: double.infinity,
        color: AppTheme.warning.withValues(alpha: 0.10),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: const Text(
          'Sin conexión con la IA — responda con los botones o el teclado.',
          style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        ),
      );

  /// Saludo OS1: la palomilla se presenta antes de preguntar (prototipo v4).
  Widget _greetingConsole() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Hola. Soy Vendi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.2,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          const Text('Vamos a crear su tienda, solo conversando.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
          const SizedBox(height: 14),
          TextButton(
            key: const Key('os1_empezar'),
            onPressed: () => setState(() => _showGreeting = false),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: const Text('Empezar',
                style:
                    TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Loader del póster: 3 guiones que se llenan con la gama de azules.
  Widget _loaderDashes() {
    final progress = _ctrl.canRegister
        ? kOnboardingQuestions.length
        : (_showGreeting ? 0 : firstUnansweredIndex(_ctrl, _answered));
    const fills = [Color(0xFFA8DEF0), Color(0xFF22C3E6), AppTheme.primary];
    return Padding(
      key: const Key('os1_loader'),
      padding: EdgeInsets.only(
          top: 4, bottom: 12 + MediaQuery.of(context).viewInsets.bottom * 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < kOnboardingQuestions.length; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 44,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: i < progress ? fills[i] : const Color(0xFFD5E6F0),
              ),
            ),
        ],
      ),
    );
  }

  Widget _questionConsole() {
    return GlassChatConsoleWidget(
      controller: _ctrl,
      question: _question,
      inputController: _inputCtrl,
      parsing: _parsing,
      recording: _recording,
      useBlur: !kIsWeb, // fallback sólido en web gama baja (Stylist)
      onAdvance: _onAdvanceText,
      onChip: _onChip,
      onSendAI: _sendText,
      onMic: _toggleMic,
    );
  }

  Widget _readyConsole() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Container(
        width: double.infinity,
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(
            24, 22, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        // Scrollable: al añadir el checkbox de T&C (Spec 098) el contenido
        // puede exceder la altura acotada de la consola en pantallas cortas
        // (360dp) — un SingleChildScrollView evita el overflow.
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¡Todo listo, ${_ctrl.ownerName}!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text('Cree su cuenta para empezar a vender.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            // Spec 098 (Fase 1): aceptación OBLIGATORIA de los Términos y
            // Servicios (incluye la cláusula de uso colaborativo de imágenes).
            // El botón "Crear mi cuenta" queda deshabilitado hasta marcarlo.
            CheckboxListTile(
              key: const Key('accept_terms_checkbox'),
              value: _ctrl.acceptedTerms,
              onChanged: _ctrl.status == StepperStatus.loading
                  ? null
                  : (v) {
                      _ctrl.setAcceptedTerms(v ?? false);
                      setState(() {});
                    },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.primary,
              title: const Text(
                'Acepto los Términos y Servicios, incluido el uso colaborativo de imágenes de producto',
                style: TextStyle(fontSize: 14, height: 1.35),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('view_terms_link'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TermsScreen()),
                ),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text(
                  'Ver términos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Spec 106 (FR-13/AC-15): aviso de datos del asistente, en
            // lenguaje llano y visible ANTES del CTA de crear la cuenta.
            const Text(
              'Al crear su cuenta, un asistente le ayudará a configurar su '
              'negocio conversando. Esa conversación se guarda para mejorar '
              'el servicio. Más detalle en la política de datos (en los '
              'términos).',
              key: Key('data_notice_text'),
              style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 64,
              child: ElevatedButton(
                key: const Key('agentic_create_account'),
                onPressed:
                    (_ctrl.status == StepperStatus.loading || !_ctrl.acceptedTerms)
                        ? null
                        : () => _ctrl.submitWithCaptcha(null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: _ctrl.status == StepperStatus.loading
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : const Text('Crear mi cuenta',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
              ),
            ),
            if (_ctrl.status == StepperStatus.error)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_ctrl.errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.error, fontSize: 14)),
              ),
          ],
          ),
        ),
      ),
    );
  }
}
