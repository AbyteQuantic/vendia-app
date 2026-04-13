import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Printer & Receipts configuration — Gerontodiseño.
/// Manages receipt header/footer text and printer MAC address.
class PrinterConfigScreen extends StatefulWidget {
  const PrinterConfigScreen({super.key});

  @override
  State<PrinterConfigScreen> createState() => _PrinterConfigScreenState();
}

class _PrinterConfigScreenState extends State<PrinterConfigScreen> {
  late final ApiService _api;
  final _headerCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _printerMac = '';

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _loadConfig();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final data = await _api.fetchStoreConfig();
      if (!mounted) return;
      setState(() {
        _headerCtrl.text = data['receipt_header'] as String? ?? '';
        _footerCtrl.text = data['receipt_footer'] as String? ?? '';
        _printerMac = data['printer_mac_address'] as String? ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await _api.updateStoreConfig({
        'receipt_header': _headerCtrl.text.trim(),
        'receipt_footer': _footerCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Configuración guardada',
            style: TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
        title: const Text('Impresora y Recibos',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Printer Status ───────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _printerMac.isEmpty
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _printerMac.isEmpty
                            ? AppTheme.error.withValues(alpha: 0.2)
                            : AppTheme.success.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _printerMac.isEmpty
                              ? Icons.print_disabled_rounded
                              : Icons.print_rounded,
                          color: _printerMac.isEmpty
                              ? AppTheme.error
                              : AppTheme.success,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _printerMac.isEmpty
                                    ? 'Sin impresora conectada'
                                    : 'Impresora conectada',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _printerMac.isEmpty
                                      ? AppTheme.error
                                      : AppTheme.success,
                                ),
                              ),
                              if (_printerMac.isNotEmpty)
                                Text(_printerMac,
                                    style: const TextStyle(
                                        fontSize: 14, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'La conexión Bluetooth requiere emparejar\nla impresora desde Ajustes del teléfono.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Receipt Header ───────────────────────────────────
                  const Text('Mensaje Superior del Recibo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('NIT, dirección, teléfono del negocio',
                      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _headerCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Ej: NIT 900.123.456-7\nCra 5 #12-34, Bogotá\nTel: 300 123 4567',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Receipt Footer ───────────────────────────────────
                  const Text('Mensaje Inferior del Recibo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  const Text('Mensaje de agradecimiento o política',
                      style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _footerCtrl,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 18, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Ej: ¡Gracias por su compra!\nVuelva pronto',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : Container(
              padding: EdgeInsets.fromLTRB(
                  24, 12, 24, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.save_rounded, size: 24),
                  label: Text(
                    _saving ? 'Guardando...' : 'Guardar Configuración',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.success.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ),
    );
  }
}
