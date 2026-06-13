// Spec: specs/045-onboarding-agentic/agentic_onboarding_animation_spec.md
//
// Bottom Console (Lead Stylist): panel inferior glassmorphic real que muestra
// UNA pregunta del agente + el cuerpo de respuesta (chips o teclado) + la
// píldora de IA (sparkle/voz). Blur estático bajo RepaintBoundary (jank #1 en
// web es animar el sigma). Reusa los setters del OnboardingStepperController.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../onboarding_stepper_controller.dart';
import 'onboarding_cards.dart' show kBusinessTypeLabels;
import 'onboarding_flow.dart';

const Color kIndigo = Color(0xFF4F46E5);

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
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  final _pinConfirm = TextEditingController();
  final _bizName = TextEditingController();
  final _address = TextEditingController();
  String _syncedFor = '';

  @override
  void dispose() {
    for (final c in [_name, _lastName, _phone, _pin, _pinConfirm, _bizName, _address]) {
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
    _name.text = c.ownerName;
    _lastName.text = c.ownerLastName;
    _phone.text = c.phone;
    _bizName.text = c.businessName;
    _address.text = c.address;
  }

  @override
  Widget build(BuildContext context) {
    _syncFields();
    final inner = Container(
      decoration: BoxDecoration(
        color: widget.useBlur
            ? Colors.white.withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(
              color: AppTheme.borderColor.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 16),
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

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          // Blur ESTÁTICO (sigma fijo) — nunca interpolado.
          child: widget.useBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: inner,
                )
              : inner,
        ),
      ),
    );
  }

  Widget _agentBubble() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.question.prompt,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
            height: 1.3,
          ),
        ),
        if (widget.question.subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            widget.question.subtitle,
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
          return _textBody([
            _field(_name, 'Su nombre', c.setOwnerName,
                key: 'q_owner_name', cap: TextCapitalization.words),
            _field(_lastName, 'Sus apellidos', c.setOwnerLastName,
                cap: TextCapitalization.words),
          ]);
        }
        if (widget.question.id == 'phone') {
          return _textBody([
            _field(_phone, 'Celular', c.setPhone,
                key: 'q_phone', keyboard: TextInputType.phone),
          ]);
        }
        // negocio
        return _textBody([
          _field(_bizName, 'Nombre del negocio', c.setBusinessName,
              key: 'q_biz_name', cap: TextCapitalization.words),
          _field(_address, 'Dirección', c.setAddress, key: 'q_biz_address'),
        ]);
      case QKind.pin:
        return _textBody([
          _field(_pin, 'Clave (4 a 8 números)', c.setPin,
              key: 'q_pin', keyboard: TextInputType.number, obscure: true, max: 8),
          _field(_pinConfirm, 'Repita la clave', c.setConfirmPin,
              key: 'q_pin_confirm',
              keyboard: TextInputType.number,
              obscure: true,
              max: 8),
        ]);
      case QKind.typeChips:
        return _chips('tipo', [
          for (final e in kBusinessTypeLabels.entries) (e.key, e.value),
        ], selected: c.businessType);
      case QKind.branchChips:
        return _chips('local', const [
          ('uno', 'No, uno solo'),
          ('varios', 'Sí, varios'),
        ], selected: c.hasMultipleBranches ? 'varios' : 'uno');
      case QKind.logoChips:
        return _chips('logo', const [
          ('generar', 'Crear con IA'),
          ('subir', 'Subir foto'),
        ]);
      case QKind.employeeChips:
        return _chips('empleados', const [
          ('no', 'No, solo yo'),
          ('si', 'Sí'),
        ], selected: c.hasEmployees == null ? null : (c.hasEmployees! ? 'si' : 'no'));
    }
  }

  Widget _textBody(List<Widget> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...fields,
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            key: const Key('console_next'),
            onPressed: widget.onAdvance,
            style: ElevatedButton.styleFrom(
              backgroundColor: kIndigo,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Siguiente',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        key: key == null ? null : Key(key),
        controller: ctrl,
        keyboardType: keyboard,
        obscureText: obscure,
        textCapitalization: cap,
        inputFormatters:
            max == null ? null : [LengthLimitingTextInputFormatter(max)],
        style: const TextStyle(fontSize: 16, color: AppTheme.textPrimary),
        decoration: InputDecoration(hintText: hint),
        onChanged: onChanged,
      ),
    );
  }

  Widget _chips(String questionId, List<(String, String)> options,
      {String? selected}) {
    // Ancho máximo del chip = todo el ancho útil menos paddings, para que una
    // etiqueta larga ("Depósito de Construcción") elipse en vez de desbordar.
    final maxChip = MediaQuery.of(context).size.width - 80;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final isSel = selected == o.$1;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('chip_${questionId}_${o.$1}'),
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onChip(questionId, o.$1);
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 56, maxWidth: maxChip),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isSel ? kIndigo.withValues(alpha: 0.10) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: isSel ? kIndigo : AppTheme.borderColor,
                      width: isSel ? 2 : 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSel) ...[
                      const Icon(Icons.check_rounded, size: 18, color: kIndigo),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(o.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isSel ? kIndigo : AppTheme.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // Píldora de IA: input libre + sparkle + voz (acelerador opcional).
  Widget _aiPill() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: AppTheme.borderColor.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'O cuénteme con sus palabras…',
                hintStyle: TextStyle(fontSize: 14),
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
                          colors: [kIndigo, Color(0xFF6366F1)])
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
