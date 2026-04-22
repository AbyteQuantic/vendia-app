import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/api_config.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Support hub screen (Phase 3 SaaS). Offers the tenant two ways to
/// reach us:
///   1. A structured form that POSTs to /api/v1/support and lands in
///      the admin `/admin/support` queue.
///   2. A WhatsApp deep-link fallback for cases where the tenant
///      prefers talking to a human in the channel they already use.
///
/// Submission callbacks are injected for testability — production wires
/// them to ApiService / url_launcher, the widget tests swap in fakes.
typedef SubmitTicketFn = Future<void> Function({
  required String subject,
  required String message,
});
typedef OpenWhatsappFn = Future<void> Function(String number);

class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    SubmitTicketFn? submitTicket,
    OpenWhatsappFn? openWhatsapp,
    String? whatsappNumber,
  })  : _submitTicket = submitTicket,
        _openWhatsapp = openWhatsapp,
        _whatsappNumber = whatsappNumber;

  final SubmitTicketFn? _submitTicket;
  final OpenWhatsappFn? _openWhatsapp;
  final String? _whatsappNumber;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  bool _submitting = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  SubmitTicketFn get _submitTicket {
    return widget._submitTicket ??
        ({required String subject, required String message}) async {
          await ApiService(AuthService()).createSupportTicket(
            subject: subject,
            message: message,
          );
        };
  }

  OpenWhatsappFn get _openWhatsapp {
    return widget._openWhatsapp ??
        (number) async {
          final uri = Uri.parse(
            'https://wa.me/$number?text=${Uri.encodeComponent('Hola, necesito soporte con VendIA')}',
          );
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        };
  }

  String get _whatsappNumber =>
      widget._whatsappNumber ?? ApiConfig.supportWhatsappNumber;

  Future<void> _onSubmit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
      _success = false;
    });

    try {
      await _submitTicket(
        subject: _subjectCtrl.text.trim(),
        message: _messageCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _success = true;
      });
      _subjectCtrl.clear();
      _messageCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'No se pudo enviar. Intente de nuevo o use WhatsApp.';
      });
    }
  }

  Future<void> _onWhatsapp() async {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    try {
      await _openWhatsapp(_whatsappNumber);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo abrir WhatsApp.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Soporte Técnico',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '¿En qué podemos ayudarte?',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cuéntanos qué está pasando y nuestro equipo te contacta.',
                  style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  key: const Key('support_subject'),
                  controller: _subjectCtrl,
                  maxLength: 160,
                  decoration: _fieldDecoration(
                    label: 'Asunto',
                    hint: 'Ej. No sincronizan las ventas',
                  ),
                  style: const TextStyle(fontSize: 18),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Ingresa un asunto' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('support_message'),
                  controller: _messageCtrl,
                  maxLines: 6,
                  decoration: _fieldDecoration(
                    label: 'Mensaje',
                    hint: '¿Qué sucedió? ¿Cuándo pasó por última vez?',
                  ),
                  style: const TextStyle(fontSize: 18),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Cuéntanos más' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    key: const Key('support_error'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.08),
                      border: Border.all(
                          color: AppTheme.error.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.error, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 15)),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_success) ...[
                  const SizedBox(height: 10),
                  Container(
                    key: const Key('support_success'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      border: Border.all(
                          color: AppTheme.success.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: AppTheme.success, size: 22),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ticket enviado. Te contactamos pronto.',
                            style: TextStyle(
                                color: AppTheme.success, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  key: const Key('support_submit'),
                  onPressed: _submitting ? null : _onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Enviar ticket',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('support_whatsapp'),
                  onPressed: _submitting ? null : _onWhatsapp,
                  icon: const Icon(Icons.chat_rounded, size: 22),
                  label: const Text('Chat por WhatsApp',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF16A34A),
                    side: const BorderSide(color: Color(0xFF16A34A)),
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
      ),
      counterText: '',
    );
  }
}
