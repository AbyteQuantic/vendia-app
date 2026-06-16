// Spec: specs/055-cuenta-mesa-whatsapp/spec.md
//
// Campo "Enviar al WhatsApp del cliente": un input de número + botón de
// enviar, pensado para el modal de la cuenta de mesa. Mantiene su propio
// estado (controller + validación mínima) y delega el envío real al
// padre vía [onSend] con el número crudo — el padre normaliza y abre
// WhatsApp con `launchWhatsapp`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WhatsappSendField extends StatefulWidget {
  /// Disparado con el texto crudo del número cuando pasa la validación.
  final void Function(String phone) onSend;

  const WhatsappSendField({super.key, required this.onSend});

  @override
  State<WhatsappSendField> createState() => _WhatsappSendFieldState();
}

class _WhatsappSendFieldState extends State<WhatsappSendField> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final digits = _ctrl.text.replaceAll(RegExp(r'[^\d]'), '');
    // 10 dígitos (celular CO) o más (ya con indicativo). Menos = inválido.
    if (digits.length < 10) {
      setState(() => _error = 'Escribe un número de WhatsApp válido');
      return;
    }
    setState(() => _error = null);
    widget.onSend(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'O envíalo al WhatsApp del cliente',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('table_qr_whatsapp_input'),
                controller: _ctrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d ()+-]')),
                ],
                decoration: InputDecoration(
                  hintText: 'Ej: 300 123 4567',
                  prefixIcon: const Icon(Icons.phone_rounded),
                  errorText: _error,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const Key('table_qr_whatsapp_send'),
                onPressed: _submit,
                icon: const Icon(Icons.send_rounded, size: 20),
                label: const Text('Enviar'),
                style: FilledButton.styleFrom(
                  // Verde WhatsApp para que se lea como "mandar por WA".
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
