// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
//
// Bottom Console (Lead Stylist): panel inferior glassmorphic real que muestra
// UNA pregunta del agente + el cuerpo de respuesta (chips o teclado) + la
// píldora de IA (sparkle/voz). Blur estático bajo RepaintBoundary (jank #1 en
// web es animar el sigma). Reusa los setters del OnboardingStepperController.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';
import 'onboarding_flow.dart';

// Spec 106 Adenda OS1: la consola dejó el glassmorphism — fondo limpio,
// pregunta centrada en tipografía liviana, campos SIN caja (solo el cursor
// parpadeando invita a escribir) y acentos en el azul de la marca.
const Color kIndigo = AppTheme.primary;

class GlassChatConsoleWidget extends StatefulWidget {
  const GlassChatConsoleWidget({
    super.key,
    required this.controller,
    required this.question,
    required this.inputController,
    required this.parsing,
    required this.recording,
    required this.useBlur,
    required this.onAdvance,
    required this.onChip,
    required this.onSendAI,
    required this.onMic,
  });

  final OnboardingStepperController controller;
  final OnboardingQuestion question;
  final TextEditingController inputController;
  final bool parsing;
  final bool recording;
  final bool useBlur;

  /// El tendero pulsó "Siguiente" en una pregunta de teclado.
  final VoidCallback onAdvance;

  /// Tocó un chip de respuesta rápida (questionId, valor).
  final void Function(String questionId, String value) onChip;

  final VoidCallback onSendAI;
  final VoidCallback onMic;

  @override
  State<GlassChatConsoleWidget> createState() => _GlassChatConsoleWidgetState();
}

class _GlassChatConsoleWidgetState extends State<GlassChatConsoleWidget> {
  // Controladores por campo, creados una vez (cursor estable). Se sincronizan
  // con el estado del controller cuando cambia la pregunta activa.
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  final _bizName = TextEditingController();
  final _address = TextEditingController();
  String _syncedFor = '';

  @override
  void dispose() {
    for (final c in [_fullName, _phone, _pin, _pinConfirm, _bizName, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Refleja el estado del controller en los campos cuando cambia la pregunta
  /// (p.ej. la IA llenó el nombre → al volver al campo aparece prellenado).
  void _syncFields() {
    if (_syncedFor == widget.question.id) return;
    _syncedFor = widget.question.id;
    final c = widget.controller;
    _fullName.text = ('${c.ownerName} ${c.ownerLastName}').trim();
    _phone.text = c.phone;
    _bizName.text = c.businessName;
    _address.text = c.address;
  }

  @override
  Widget build(BuildContext context) {
    _syncFields();
    final inner = Container(
      color: Colors.transparent,
      // El Scaffold ya re-layouta con el teclado (resize default): padding
      // fijo — sumar viewInsets aquí duplicaba el despeje (panel blanco).
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _agentBubble(),
            const SizedBox(height: 14),
            _body(),
            const SizedBox(height: 12),
            _aiPill(),
          ],
        ),
      ),
    );

    return RepaintBoundary(child: inner);
  }

  Widget _agentBubble() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          widget.question.prompt,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w300,
            color: AppTheme.textPrimary,
            height: 1.3,
            letterSpacing: -0.2,
          ),
        ),
        if (widget.question.subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.question.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15, color: AppTheme.textSecondary, height: 1.3),
          ),
        ],
      ],
    );
  }

  Widget _body() {
    final c = widget.controller;
    switch (widget.question.kind) {
      case QKind.text:
        if (widget.question.id == 'owner') {
          // Spec 106 (2026-07-19): UNA sola caja — el sistema separa
          // nombre/apellidos (setOwnerFullName); cero fricción (Art. I).
          return _textBody([
            _field(_fullName, '', c.setOwnerFullName,
                key: 'q_owner_name', cap: TextCapitalization.words,
                autofocus: true),
          ]);
        }
        if (widget.question.id == 'phone') {
          return _textBody([
            _field(_phone, '', c.setPhone,
                key: 'q_phone', keyboard: TextInputType.phone, autofocus: true),
          ]);
        }
        // Fallback defensivo (no debería alcanzarse con el flujo de 3
        // preguntas de Spec 106).
        return _textBody([
          _field(_bizName, 'Nombre del negocio', c.setBusinessName,
              key: 'q_biz_name', cap: TextCapitalization.words),
          _field(_address, 'Dirección', c.setAddress, key: 'q_biz_address'),
        ]);
      case QKind.pin:
        return _textBody([
          _field(_pin, 'Clave', c.setPin,
              key: 'q_pin', keyboard: TextInputType.number, obscure: true,
              max: 8, autofocus: true),
          _field(_pinConfirm, 'Repita la clave', c.setConfirmPin,
              key: 'q_pin_confirm',
              keyboard: TextInputType.number,
              obscure: true,
              max: 8),
        ]);
      // Spec 106: los QKind de chips (tipo/local/logo/empleados) se retiraron
      // — esa configuración ahora la hace Vendi conversando tras el registro.
    }
  }

  Widget _textBody(List<Widget> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...fields,
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: TextButton(
            key: const Key('console_next'),
            onPressed: widget.onAdvance,
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: const Text('Siguiente',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    ValueChanged<String> onChanged, {
    String? key,
    TextInputType? keyboard,
    bool obscure = false,
    int? max,
    TextCapitalization cap = TextCapitalization.none,
    bool autofocus = false,
  }) {
    // OS1: sin caja, sin borde, sin fondo — texto centrado y el cursor azul
    // parpadeando como única invitación a escribir.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextField(
        key: key == null ? null : Key(key),
        controller: ctrl,
        keyboardType: keyboard,
        obscureText: obscure,
        textCapitalization: cap,
        autofocus: autofocus,
        textAlign: TextAlign.center,
        cursorColor: AppTheme.primary,
        cursorWidth: 1.6,
        inputFormatters:
            max == null ? null : [LengthLimitingTextInputFormatter(max)],
        style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w400, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          // OS1: sin placeholder — el cursor parpadeando ES la invitación.
          hintText: hint.isEmpty ? null : hint,
          hintStyle: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w300, color: AppTheme.textSecondary),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _aiPill() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          _circle(
            key: const Key('console_mic'),
            icon: widget.recording ? Icons.stop_rounded : Icons.mic_none_rounded,
            color: widget.recording ? AppTheme.error : kIndigo,
            filled: widget.recording,
            onTap: widget.onMic,
          ),
          Expanded(
            child: TextField(
              key: const Key('console_ai_input'),
              controller: widget.inputController,
              minLines: 1,
              maxLines: 2,
              textAlign: TextAlign.center,
              cursorColor: AppTheme.primary,
              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                hintText: 'O cuénteme con sus palabras…',
                hintStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w300,
                    color: AppTheme.textSecondary),
              ),
              onSubmitted: (_) => widget.onSendAI(),
            ),
          ),
          _circle(
            key: const Key('console_send'),
            icon: Icons.auto_awesome,
            color: kIndigo,
            filled: true,
            loading: widget.parsing,
            onTap: widget.onSendAI,
          ),
        ],
      ),
    );
  }

  Widget _circle({
    required Key key,
    required IconData icon,
    required Color color,
    required bool filled,
    bool loading = false,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        key: key,
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: Ink(
          decoration: filled
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: color == kIndigo
                      ? const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent])
                      : null,
                  color: color == kIndigo ? null : color,
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
                    size: 22, color: filled ? Colors.white : color),
          ),
        ),
      ),
    );
  }
}
