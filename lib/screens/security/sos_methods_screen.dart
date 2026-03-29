import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'sos_message_screen.dart';

class SosMethodsScreen extends StatefulWidget {
  const SosMethodsScreen({super.key});

  @override
  State<SosMethodsScreen> createState() => _SosMethodsScreenState();
}

class _SosMethodsScreenState extends State<SosMethodsScreen> {
  bool _smsEnabled = true;
  bool _whatsappEnabled = false;
  bool _callEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBFF),
      body: Column(
        children: [
          // ── Header ──
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFDC2626)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.only(
              top: 48 + 20,
              left: 20,
              right: 20,
              bottom: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Semantics(
                      label: 'Volver atrás',
                      button: true,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.pop(context);
                        },
                        child: const SizedBox(
                          width: 60,
                          height: 60,
                          child: Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '\u{00BF}Cómo quiere avisar?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    'Active los métodos que prefiera',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildToggleCard(
                    emoji: '\u{1F4AC}',
                    title: 'Enviar SMS',
                    subtitle: 'Mensaje de texto al número configurado',
                    value: _smsEnabled,
                    semanticsLabel: 'Activar envío de SMS de emergencia',
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _smsEnabled = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildToggleCard(
                    emoji: '\u{1F7E2}',
                    title: 'Mensaje por WhatsApp',
                    subtitle: 'Enviamos un mensaje automático',
                    value: _whatsappEnabled,
                    semanticsLabel: 'Activar envío de WhatsApp de emergencia',
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _whatsappEnabled = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildToggleCard(
                    emoji: '\u{1F4DE}',
                    title: 'Llamada Automática',
                    subtitle:
                        'Una voz inteligente dará su dirección por usted.',
                    subtitleItalic: 'No necesita hablar.',
                    value: _callEnabled,
                    semanticsLabel: 'Activar llamada automática de emergencia',
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _callEnabled = v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom Button ──
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFF),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Semantics(
          label: 'Siguiente paso',
          button: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SosMessageScreen(),
                ),
              );
            },
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const Text(
                'Siguiente \u{2192}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleCard({
    required String emoji,
    required String title,
    required String subtitle,
    String? subtitleItalic,
    required bool value,
    required String semanticsLabel,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 100),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF9CA3AF),
                    ),
                    children: [
                      TextSpan(text: subtitle),
                      if (subtitleItalic != null) ...[
                        const TextSpan(text: ' '),
                        TextSpan(
                          text: subtitleItalic,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            label: semanticsLabel,
            toggled: value,
            child: Transform.scale(
              scale: 1.4,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: const Color(0xFF10B981),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
