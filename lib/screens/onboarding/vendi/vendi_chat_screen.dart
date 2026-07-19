// Spec: specs/106-onboarding-conversacional-agente/spec.md
//
// Pantalla de conversación con Vendi: el tendero configura su negocio
// hablando, no escogiendo opciones. Reemplaza al onboarding F045 (AC-01).
// Diseño aprobado en el prototipo del fundador: header con avatar de marca,
// burbujas, chips de respuesta rápida, input inferior. Probado a 360dp.
import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../services/auth_service.dart';
import '../../../theme/app_theme.dart';
import 'vendi_chat_controller.dart';
import 'type_fallback_screen.dart';

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
  final _scrollCtrl = ScrollController();
  bool _navigated = false;

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
    _ctrl.start();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
    if (_ctrl.done && !_navigated) {
      _navigated = true;
      // Breve pausa para que se lea el mensaje final antes de navegar.
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) widget.onCompleted();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    if (widget.controllerOverride == null) _ctrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FB),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _chatList()),
            if (_ctrl.offerFallback) _fallbackBanner(),
            if (_ctrl.chips.isNotEmpty) _chipsRow(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, Color(0xFF1490C4), AppTheme.accent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          const VendiAvatar(key: Key('vendi_avatar'), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Vendi',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                Row(children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: Color(0xFF7BF2B0), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  const Flexible(
                    child: Text('Su asistente para crear la tienda',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatList() {
    final items = <Widget>[
      for (final m in _ctrl.messages) _bubble(m),
      if (_ctrl.busy) _typingBubble(),
      if (_ctrl.proposalGrid.isNotEmpty && !_ctrl.busy) _proposalCard(),
    ];
    return ListView(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      children: items,
    );
  }

  Widget _bubble(VendiMessage m) {
    final isUser = m.role == VendiRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 290),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 16),
          ),
          border: isUser ? null : Border.all(color: const Color(0xFFDCE8F0)),
        ),
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: isUser ? Colors.white : const Color(0xFF16303F),
            ),
            children: parseVendiTags(m.text),
          ),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('vendi_typing'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDCE8F0)),
        ),
        child: const _TypingDots(),
      ),
    );
  }

  Widget _proposalCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFE4F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Así quedaría su tienda:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _ctrl.proposalGrid) _moduleChip(m, false),
              for (final m in _ctrl.proposalReel) _moduleChip('✨ $m', true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _moduleChip(String label, bool reel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: reel ? const Color(0xFFFDF3E7) : const Color(0xFFEAF6FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: reel ? const Color(0xFFF0D9B8) : const Color(0xFFBFE4F2)),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: reel ? const Color(0xFF9A5E14) : const Color(0xFF0B5D8F),
          )),
    );
  }

  Widget _fallbackBanner() {
    return Container(
      width: double.infinity,
      color: AppTheme.warning.withValues(alpha: 0.10),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'La IA no está disponible en este momento.',
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              key: const Key('vendi_fallback_cta'),
              onPressed: _goFallback,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Escoger yo mismo los tipos de mi negocio',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final chip in _ctrl.chips)
            OutlinedButton(
              key: Key('vendi_chip_${chip.id}'),
              onPressed: _ctrl.busy
                  ? null
                  : () => _ctrl.tapChip(chip.id, chip.label),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0B5D8F),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF1490C4), width: 1.5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
              ),
              child: Text(chip.label,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE0EAF1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('vendi_input'),
              controller: _inputCtrl,
              enabled: !_ctrl.done,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Escriba su respuesta…',
                hintStyle: const TextStyle(color: Color(0xFF8AA2B2)),
                filled: true,
                fillColor: const Color(0xFFF7FAFC),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: const BorderSide(color: Color(0xFFC9DAE6)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide:
                      const BorderSide(color: Color(0xFFC9DAE6), width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 48,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.accent]),
                ),
                child: InkWell(
                  key: const Key('vendi_send'),
                  customBorder: const CircleBorder(),
                  onTap: _ctrl.busy || _ctrl.done ? null : _send,
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar de Vendi: círculo con gradiente de marca y carita sonriente
/// (identidad aprobada del prototipo del fundador).
class VendiAvatar extends StatelessWidget {
  const VendiAvatar({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 1.2,
          colors: [Color(0xFF8FE9FB), AppTheme.accent, AppTheme.primary],
        ),
      ),
      child: CustomPaint(painter: _VendiFacePainter()),
    );
  }
}

class _VendiFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final eye = Paint()..color = Colors.white;
    final pupil = Paint()..color = const Color(0xFF0E3A57);
    canvas.drawCircle(Offset(w * 0.36, h * 0.42), w * 0.075, eye);
    canvas.drawCircle(Offset(w * 0.64, h * 0.42), w * 0.075, eye);
    canvas.drawCircle(Offset(w * 0.375, h * 0.435), w * 0.032, pupil);
    canvas.drawCircle(Offset(w * 0.655, h * 0.435), w * 0.032, pupil);
    final smile = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.06
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(w * 0.34, h * 0.62)
      ..quadraticBezierTo(w * 0.5, h * 0.74, w * 0.66, h * 0.62);
    canvas.drawPath(path, smile);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tres puntos animados del indicador "escribiendo".
class _TypingDots extends StatefulWidget {
  const _TypingDots();

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
    )..repeat();
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
            final opacity = phase < 0.4 ? 0.35 + phase * 1.6 : 1.0 - (phase - 0.4);
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
          ? const TextStyle(fontWeight: FontWeight.w800)
          : const TextStyle(fontStyle: FontStyle.italic),
    ));
    cursor = m.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}
