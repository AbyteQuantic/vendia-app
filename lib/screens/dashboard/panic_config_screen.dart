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
  bool _includeAddress = true;
  bool _includeGPS = true;

  static const _presetMessages = [
    'EMERGENCIA en el local. Necesito ayuda policial inmediata.',
    'Actividad sospechosa en el negocio. Por favor llamar al local.',
    'Robo en curso. Enviar patrulla urgente.',
  ];

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _msgCtrl.addListener(() => setState(() {}));
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
          _includeAddress = res['panic_include_address'] as bool? ?? true;
          _includeGPS = res['panic_include_gps'] as bool? ?? true;
          _contacts = (res['contacts'] as List?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _buildPreview() {
    final msg = _msgCtrl.text.trim().isNotEmpty
        ? _msgCtrl.text.trim()
        : 'EMERGENCIA en el local. Necesito ayuda inmediata.';
    final parts = <String>[msg];
    if (_includeAddress) parts.add('\nDireccion: Cra 5 #12-34, Bogota');
    if (_includeGPS) {
      parts.add('\nUbicacion: https://maps.google.com/?q=4.60,-74.08');
    }
    return parts.join('');
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await _api.updatePanicMessage(
        _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
        includeAddress: _includeAddress,
        includeGPS: _includeGPS,
      );
      if (mounted) {
        _showSnack('Configuracion de seguridad actualizada');
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) _showSnack('Error al guardar', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 16)),
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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
                Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: const Color(0xFFD6D0C8),
                        borderRadius: BorderRadius.circular(2))),
                const Text('Nuevo Contacto',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                  decoration: const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.person_rounded)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                  decoration: const InputDecoration(
                      labelText: 'Telefono',
                      prefixIcon: Icon(Icons.phone_rounded)),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  _methodChip('WhatsApp', 'whatsapp', method,
                      const Color(0xFF25D366), (v) => setSheet(() => method = v)),
                  const SizedBox(width: 10),
                  _methodChip('SMS', 'sms', method, AppTheme.primary,
                      (v) => setSheet(() => method = v)),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          phoneCtrl.text.trim().length < 7) return;
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
                    label: const Text('Agregar',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.error,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _methodChip(String label, String value, String current, Color color,
      ValueChanged<String> onTap) {
    final sel = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: sel ? color.withValues(alpha: 0.1) : AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: sel ? color : AppTheme.borderColor,
                width: sel ? 2 : 1),
          ),
          child: Center(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: sel ? color : Colors.black87))),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(children: [
          Icon(Icons.emergency_rounded, color: AppTheme.error, size: 24),
          SizedBox(width: 10),
          Text('Boton de Panico',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary)),
        ]),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.error))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ═══════════════════════════════════════════════════
                  // SECTION 1: Que mensaje enviar
                  // ═══════════════════════════════════════════════════
                  _sectionCard(
                    number: '1',
                    title: 'Que mensaje enviar',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                            'Seleccione una plantilla o escriba su propio mensaje',
                            style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _presetMessages
                              .map((msg) => GestureDetector(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      setState(() => _msgCtrl.text = msg);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: _msgCtrl.text == msg
                                            ? AppTheme.error
                                                .withValues(alpha: 0.12)
                                            : AppTheme.error
                                                .withValues(alpha: 0.04),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: _msgCtrl.text == msg
                                                ? AppTheme.error
                                                : AppTheme.error
                                                    .withValues(alpha: 0.15),
                                            width:
                                                _msgCtrl.text == msg ? 2 : 1),
                                      ),
                                      child: Text(msg,
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: AppTheme.error,
                                              fontWeight:
                                                  _msgCtrl.text == msg
                                                      ? FontWeight.w700
                                                      : FontWeight.normal)),
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _msgCtrl,
                          maxLines: 3,
                          style: const TextStyle(
                              fontSize: 18, color: Colors.black87),
                          decoration: InputDecoration(
                            hintText: 'Escriba su mensaje...',
                            hintStyle:
                                TextStyle(color: Colors.grey.shade400),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════
                  // SECTION 2: Donde estoy
                  // ═══════════════════════════════════════════════════
                  _sectionCard(
                    number: '2',
                    title: 'Donde estoy (Ubicacion)',
                    child: Column(children: [
                      _switchTile(
                        icon: Icons.home_rounded,
                        title: 'Incluir direccion del negocio',
                        subtitle: 'Envia la direccion registrada en el perfil',
                        value: _includeAddress,
                        onChanged: (v) =>
                            setState(() => _includeAddress = v),
                      ),
                      const Divider(height: 1, indent: 48),
                      _switchTile(
                        icon: Icons.gps_fixed_rounded,
                        title: 'Incluir ubicacion GPS en vivo',
                        subtitle:
                            'Envia un link de Google Maps con la posicion actual',
                        value: _includeGPS,
                        onChanged: (v) => setState(() => _includeGPS = v),
                      ),
                    ]),
                  ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════
                  // PREVIEW
                  // ═══════════════════════════════════════════════════
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: AppTheme.success.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.visibility_rounded,
                              size: 18,
                              color:
                                  AppTheme.success.withValues(alpha: 0.7)),
                          const SizedBox(width: 6),
                          Text('Vista previa',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.success
                                      .withValues(alpha: 0.7))),
                        ]),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(_buildPreview(),
                              style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                  height: 1.5)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                            'Se enviara a ${_contacts.length} contacto${_contacts.length != 1 ? "s" : ""}',
                            style: TextStyle(
                                fontSize: 13,
                                color:
                                    AppTheme.success.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════
                  // SECTION 3: A quien avisar
                  // ═══════════════════════════════════════════════════
                  _sectionCard(
                    number: '3',
                    title: 'A quien avisar (${_contacts.length}/5)',
                    child: Column(children: [
                      for (final c in _contacts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    AppTheme.error.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                  (c['contact_method'] as String?) == 'sms'
                                      ? Icons.sms_rounded
                                      : Icons.chat_rounded,
                                  color: AppTheme.error,
                                  size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(c['name'] as String? ?? '',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87)),
                                  Text(c['phone_number'] as String? ?? '',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await _api.deleteEmergencyContact(
                                    c['id'] as String);
                                _load();
                              },
                              icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppTheme.error,
                                  size: 20),
                            ),
                          ]),
                        ),
                      if (_contacts.length < 5)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _showAddContact,
                            icon: const Icon(Icons.person_add_rounded,
                                color: AppTheme.error, size: 20),
                            label: const Text('Agregar Contacto',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.error)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.error),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 80), // space for bottom button
                ],
              ),
            ),
      // ── Global save button ─────────────────────────────────────────────
      bottomNavigationBar: _loading
          ? null
          : Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBF7),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -2)),
                ],
              ),
              child: SizedBox(
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveAll,
                  icon: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.shield_rounded, size: 24),
                  label: Text(
                    _saving
                        ? 'Guardando...'
                        : 'Guardar Configuracion de Seguridad',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppTheme.error.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionCard(
      {required String number, required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: Text(number,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.error))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
            ),
          ]),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, color: AppTheme.error, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary)),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppTheme.error,
        ),
      ]),
    );
  }
}
