// Spec: specs/106-onboarding-conversacional-agente/spec.md (Adenda OS1)
//
// Conversación con Vendi en la dirección visual "Her/OS1" aprobada por el
// fundador (2026-07-19): cero burbujas y cero cajas — el símbolo vivo
// (VendiOrb) preside la pantalla y se transforma según la fase de la
// conversación; el diálogo del asistente aparece centrado en tipografía
// liviana; los chips son texto azul; el input es una línea sin borde con el
// cursor parpadeando como única invitación a escribir.
import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import 'type_fallback_screen.dart';
import 'vendi_chat_controller.dart';
import 'vendi_orb.dart';

class VendiChatScreen extends StatefulWidget {
  const VendiChatScreen({
    super.key,
    required this.onCompleted,
    this.controllerOverride,
    this.onFallback,
  });

  /// Se invoca cuando la tienda quedó configurada (ir al Dashboard).
  final VoidCallback onCompleted;

  /// Controller inyectable para tests; en producción se construye con la API.
  final VendiChatController? controllerOverride;

  /// Override del camino manual (tests); default: navega a TypeFallbackScreen.
  final VoidCallback? onFallback;

  @override
  State<VendiChatScreen> createState() => _VendiChatScreenState();
}

class _VendiChatScreenState extends State<VendiChatScreen> {
  late final VendiChatController _ctrl;
  late final ApiService _api = ApiService(AuthService());
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  bool _navigated = false;
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controllerOverride ??
        VendiChatController(
          turnCall: ({sessionId, text, chip}) =>
              _api.agentTurn(sessionId: sessionId, text: text, chip: chip),
          confirmCall: (sessionId) => _api.agentConfirm(sessionId),
        );
    _ctrl.addListener(_onChange);
    _inputCtrl.addListener(() {
      final t = _inputCtrl.text.isNotEmpty;
      if (t != _typing && mounted) setState(() => _typing = t);
    });
    _ctrl.start();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    // El cursor parpadeando ES la invitación a escribir (OS1): al terminar
    // cada turno sin chips, el foco vuelve solo al campo.
    if (!_ctrl.busy && !_ctrl.done && _ctrl.chips.isEmpty) {
      _inputFocus.requestFocus();
    }
    if (_ctrl.done && !_navigated) {
      _navigated = true;
      // Breve pausa para que se lea el cierre (y el corazón) antes de salir.
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (mounted) widget.onCompleted();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    if (widget.controllerOverride == null) _ctrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _ctrl.busy) return;
    _inputCtrl.clear();
    _ctrl.sendText(text);
  }

  void _goFallback() {
    if (widget.onFallback != null) {
      widget.onFallback!();
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TypeFallbackScreen(
        sessionId: _ctrl.sessionId,
        onCompleted: widget.onCompleted,
      ),
    ));
  }

  /// El símbolo acompaña la fase: tienda cuando se habla del negocio o de la
  /// propuesta, corazón al terminar, y la palomilla — la identidad de Vendi —
  /// mientras conversa e interpreta.
  VendiOrbShape get _orbShape {
    if (_ctrl.done) return VendiOrbShape.heart;
    switch (_ctrl.phase) {
      case 'ask_name':
      case 'propose':
        return VendiOrbShape.store;
      default:
        return VendiOrbShape.palomilla;
    }
  }

  /// Bloque final de mensajes del asistente (el "diálogo" OS1: lo último que
  /// dijo Vendi, no un historial de burbujas).
  List<VendiMessage> get _lastAssistantBlock {
    final out = <VendiMessage>[];
    for (var i = _ctrl.messages.length - 1; i >= 0; i--) {
      final m = _ctrl.messages[i];
      if (m.role != VendiRole.assistant) break;
      out.insert(0, m);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // Gradiente fuera del Scaffold + resize default: en iOS web,
    // resize:false hace que el navegador panee la página al abrir el
    // teclado y se pierda todo el contenido.
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7FBFD), Color(0xFFEAF4FA)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              VendiOrb(
                key: const Key('vendi_avatar'),
                shape: _orbShape,
                size: 150,
                listening: _ctrl.busy || _typing,
              ),
              const Text(
                'Vendi',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              // OS1: el campo fluye JUSTO debajo del diálogo (como en el
              // registro), no pegado al borde inferior de la pantalla.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 12),
                  child: Column(
                    children: [
                      _dialogue(),
                      if (_ctrl.offerFallback) _fallbackCta(),
                      if (_ctrl.chips.isNotEmpty) _chipsRow(),
                      if (!_ctrl.done && _ctrl.chips.isEmpty) _inputBar(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogue() {
    return Column(
        children: [
          for (final m in _lastAssistantBlock)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.35,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.2,
                    color: AppTheme.textPrimary,
                  ),
                  children: parseVendiTags(m.text),
                ),
              ),
            ),
          if (_ctrl.busy)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: _TypingDots(key: Key('vendi_typing')),
            ),
          if (_ctrl.proposalGrid.isNotEmpty && !_ctrl.busy) _proposal(),
        ],
    );
  }

  Widget _proposal() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final m in _ctrl.proposalGrid) _moduleChip(m, false),
          for (final m in _ctrl.proposalReel) _moduleChip('✨ $m', true),
        ],
      ),
    );
  }

  Widget _moduleChip(String label, bool reel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: reel ? const Color(0xFFF0D9B8) : const Color(0xFFBFE4F2),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: reel ? const Color(0xFF9A5E14) : const Color(0xFF0B5D8F),
        ),
      ),
    );
  }

  Widget _fallbackCta() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 6),
      child: Column(
        children: [
          const Text(
            'La IA no está disponible en este momento.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          TextButton(
            key: const Key('vendi_fallback_cta'),
            onPressed: _goFallback,
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: const Text(
              'Escoger yo mismo los tipos de mi negocio',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          for (final chip in _ctrl.chips)
            TextButton(
              key: Key('vendi_chip_${chip.id}'),
              onPressed:
                  _ctrl.busy ? null : () => _ctrl.tapChip(chip.id, chip.label),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: Text(
                chip.label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('vendi_input'),
              controller: _inputCtrl,
              focusNode: _inputFocus,
              enabled: !_ctrl.done,
              autofocus: true,
              textAlign: TextAlign.center,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              cursorColor: AppTheme.primary,
              cursorWidth: 1.6,
              style: const TextStyle(fontSize: 18, color: AppTheme.textPrimary),
              // OS1: sin placeholder — el cursor azul parpadeando (autofocus)
              // señala dónde escribir, como en el prototipo aprobado.
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
          IconButton(
            key: const Key('vendi_send'),
            onPressed: _ctrl.busy || _ctrl.done ? null : _send,
            color: AppTheme.primary,
            icon: const Icon(Icons.send_rounded, size: 24),
          ),
        ],
      ),
    );
  }
}

/// Tres puntos animados del indicador "pensando/escribiendo".
class _TypingDots extends StatefulWidget {
  const _TypingDots({super.key});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  // Creado en initState (no `late final` perezoso): inicializarlo en un
  // dispose sin build previo crearía el Ticker durante el desmontaje.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final reduce =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    if (!reduce) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value - i * 0.18) % 1.0;
            final opacity =
                phase < 0.4 ? 0.35 + phase * 1.6 : 1.0 - (phase - 0.4);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: const Color(0xFF8FA9BA)
                    .withValues(alpha: opacity.clamp(0.25, 1.0)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}

/// Convierte el marcado mínimo del backend (<b>…</b>, <i>…</i>) en TextSpans.
/// Cualquier otra etiqueta se muestra como texto plano (no se interpreta HTML).
List<TextSpan> parseVendiTags(String text) {
  final spans = <TextSpan>[];
  final regex = RegExp(r'<(b|i)>(.*?)<\/\1>', dotAll: true);
  var cursor = 0;
  for (final m in regex.allMatches(text)) {
    if (m.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, m.start)));
    }
    spans.add(TextSpan(
      text: m.group(2),
      style: m.group(1) == 'b'
          ? const TextStyle(fontWeight: FontWeight.w600)
          : const TextStyle(fontStyle: FontStyle.italic),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}
