import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class PanicConfigScreen extends StatefulWidget {
  const PanicConfigScreen({super.key});

  @override
  State<PanicConfigScreen> createState() => _PanicConfigScreenState();
}

class _PanicConfigScreenState extends State<PanicConfigScreen> {
  late final ApiService _api;
  final _msgCtrl = TextEditingController();
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;
  bool _saving = false;

  static const _presetMessages = [
    'EMERGENCIA en el local. Necesito ayuda policial inmediata.',
    'Actividad sospechosa en el negocio. Por favor llamar al local.',
    'Robo en curso. Enviar patrulla urgente.',
  ];

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.fetchPanicConfig();
      if (mounted) {
        setState(() {
          _msgCtrl.text = res['panic_message'] as String? ?? '';
          _contacts = (res['contacts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveMessage() async {
    if (_msgCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await _api.updatePanicMessage(_msgCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Mensaje guardado', style: TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
    if (mounted) setState(() => _saving = false);
  }

  void _showAddContact() {
    if (_contacts.length >= 5) return;
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String method = 'whatsapp';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: StatefulBuilder(
            builder: (ctx, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: const Color(0xFFD6D0C8),
                        borderRadius: BorderRadius.circular(2))),
                const Text('Nuevo Contacto de Emergencia',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                  decoration: const InputDecoration(
                      labelText: 'Nombre (ej: Cuadrante Policia)',
                      prefixIcon: Icon(Icons.person_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                  decoration: const InputDecoration(
                      labelText: 'Numero de telefono',
                      prefixIcon: Icon(Icons.phone_rounded)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheet(() => method = 'whatsapp'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: method == 'whatsapp'
                                ? const Color(0xFF25D366).withValues(alpha: 0.1)
                                : AppTheme.surfaceGrey,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: method == 'whatsapp'
                                    ? const Color(0xFF25D366)
                                    : AppTheme.borderColor,
                                width: method == 'whatsapp' ? 2 : 1),
                          ),
                          child: const Center(child: Text('WhatsApp',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheet(() => method = 'sms'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: method == 'sms'
                                ? AppTheme.primary.withValues(alpha: 0.1)
                                : AppTheme.surfaceGrey,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: method == 'sms'
                                    ? AppTheme.primary : AppTheme.borderColor,
                                width: method == 'sms' ? 2 : 1),
                          ),
                          child: const Center(child: Text('SMS',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().length < 7) return;
                      Navigator.of(ctx).pop();
                      try {
                        await _api.createEmergencyContact({
                          'name': nameCtrl.text.trim(),
                          'phone_number': phoneCtrl.text.trim(),
                          'contact_method': method,
                        });
                        _load();
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Agregar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7), elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(children: [
          Icon(Icons.emergency_rounded, color: AppTheme.error, size: 24),
          SizedBox(width: 10),
          Text('Boton de Panico', style: TextStyle(fontSize: 22,
              fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.error))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Message section ─────────────────────────────────
                const Text('Mensaje de emergencia',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                const Text('Se enviara a todos sus contactos al activar la alerta',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: _presetMessages.map((msg) => GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _msgCtrl.text = msg);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
                      ),
                      child: Text(msg, style: const TextStyle(fontSize: 14, color: AppTheme.error)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _msgCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 18, color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Escriba su mensaje de emergencia...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveMessage,
                    icon: const Icon(Icons.save_rounded, size: 20),
                    label: Text(_saving ? 'Guardando...' : 'Guardar mensaje',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Contacts section ────────────────────────────────
                Row(
                  children: [
                    const Expanded(child: Text('Contactos de emergencia',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary))),
                    Text('${_contacts.length}/5',
                        style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 12),

                for (final c in _contacts)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          (c['contact_method'] as String?) == 'sms'
                              ? Icons.sms_rounded : Icons.chat_rounded,
                          color: AppTheme.error, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['name'] as String? ?? '', style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600, color: Colors.black87)),
                          Text(c['phone_number'] as String? ?? '', style: const TextStyle(
                              fontSize: 14, color: AppTheme.textSecondary)),
                        ],
                      )),
                      IconButton(
                        onPressed: () async {
                          await _api.deleteEmergencyContact(c['id'] as String);
                          _load();
                        },
                        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 22),
                      ),
                    ]),
                  ),

                if (_contacts.length < 5) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: OutlinedButton.icon(
                      onPressed: _showAddContact,
                      icon: const Icon(Icons.person_add_rounded, color: AppTheme.error),
                      label: const Text('Agregar Contacto',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.error)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.error, width: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
