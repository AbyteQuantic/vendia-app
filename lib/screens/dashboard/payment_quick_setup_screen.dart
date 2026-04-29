import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Express payment-config for the tendero — the single-method path that
/// the public fiado portal reads. Replaces the multi-row CRUD for the
/// "most common" use case: 95 % of tenderos only have one Nequi or
/// Daviplata account and want a 30-second setup.
class PaymentQuickSetupScreen extends StatefulWidget {
  const PaymentQuickSetupScreen({super.key});

  @override
  State<PaymentQuickSetupScreen> createState() =>
      _PaymentQuickSetupScreenState();
}

class _PaymentQuickSetupScreenState extends State<PaymentQuickSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  String _method = 'Nequi';
  bool _loading = true;
  bool _saving = false;
  late final ApiService _api;

  static const _methods = <_MethodOption>[
    _MethodOption(
        id: 'Nequi',
        label: 'Nequi',
        icon: Icons.smartphone_rounded,
        color: Color(0xFFE5007E),
        numericOnly: true),
    _MethodOption(
        id: 'Daviplata',
        label: 'Daviplata',
        icon: Icons.smartphone_rounded,
        color: Color(0xFFE2001A),
        numericOnly: true),
    _MethodOption(
        id: 'Bancolombia',
        label: 'Bancolombia',
        icon: Icons.account_balance_rounded,
        color: Color(0xFFFDDA24),
        numericOnly: true),
    _MethodOption(
        id: 'Davivienda',
        label: 'Davivienda',
        icon: Icons.account_balance_rounded,
        color: Color(0xFFED1C24),
        numericOnly: true),
    _MethodOption(
        id: 'Bancolombia a la Mano',
        label: 'Bancolombia a la Mano',
        icon: Icons.smartphone_rounded,
        color: Color(0xFFFDDA24),
        numericOnly: true),
    _MethodOption(
        id: 'Efectivo',
        label: 'Efectivo (sin cuenta)',
        icon: Icons.payments_rounded,
        color: Color(0xFF059669),
        numericOnly: false),
  ];

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _prefill();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _holderCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    try {
      final data = await _api.fetchBusinessProfile()
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final name = (data['payment_method_name'] as String? ?? '').trim();
      setState(() {
        if (name.isNotEmpty && _methods.any((m) => m.id == name)) {
          _method = name;
        }
        _numberCtrl.text =
            (data['payment_account_number'] as String? ?? '').trim();
        _holderCtrl.text =
            (data['payment_account_holder'] as String? ?? '').trim();
        _loading = false;
      });
    } catch (e) {
      debugPrint('[COBRO_DIGITAL] prefill error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  _MethodOption get _selectedMethod =>
      _methods.firstWhere((m) => m.id == _method, orElse: () => _methods[0]);

  bool get _isCash => _selectedMethod.id == 'Efectivo';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _api.updatePaymentConfig(
        methodName: _method,
        accountNumber: _isCash ? '' : _numberCtrl.text.trim(),
        accountHolder: _isCash ? '' : _holderCtrl.text.trim(),
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Cobro digital habilitado',
            style: TextStyle(fontSize: 16)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop(true);
    } on AppError catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo guardar: ${e.message}',
            style: const TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo guardar: $e',
            style: const TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFFBF7),
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

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
        title: const Text('Cobro Digital',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              // Context card — why this matters
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppTheme.primary, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Configure sus datos de pago. Sus clientes verán estos datos en su cuenta del fiado para pagarle sin errores.',
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Method dropdown ─────────────────────────────────────
              const Text('¿Por dónde cobra?',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _method,
                style: const TextStyle(
                    fontSize: 18,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: Icon(_selectedMethod.icon,
                      color: _selectedMethod.color, size: 28),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEDE8E0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEDE8E0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: AppTheme.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                ),
                items: _methods
                    .map((m) => DropdownMenuItem<String>(
                          value: m.id,
                          child: Row(
                            children: [
                              Icon(m.icon, color: m.color, size: 22),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(m.label,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _method = v);
                },
              ),
              const SizedBox(height: 22),

              if (!_isCash) ...[
                const Text('Número de cuenta o celular',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _numberCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1),
                  decoration: InputDecoration(
                    hintText: 'Ej: 3001234567',
                    hintStyle: TextStyle(
                        fontSize: 18, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.pin_rounded,
                        color: AppTheme.primary, size: 24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFEDE8E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFEDE8E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AppTheme.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 16),
                  ),
                  validator: (v) {
                    if (_isCash) return null;
                    final val = (v ?? '').trim();
                    if (val.isEmpty) return 'Ingrese el número';
                    if (val.length < 7) return 'Número muy corto';
                    return null;
                  },
                ),
                const SizedBox(height: 22),

                const Text('Nombre del titular (opcional pero recomendado)',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _holderCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Ej: María Pérez',
                    hintStyle: TextStyle(
                        fontSize: 17, color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.person_outline_rounded,
                        color: AppTheme.textSecondary, size: 24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFEDE8E0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFEDE8E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: AppTheme.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.35),
                        width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          color: AppTheme.warning.withValues(alpha: 0.9),
                          size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'El nombre ayuda a que sus clientes confirmen que están pagando a la cuenta correcta.',
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.payments_rounded,
                          color: Color(0xFF059669), size: 26),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Solo efectivo: el deudor no verá botones para copiar; deberá acordar el pago directamente con usted.',
                          style: TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),
              SizedBox(
                height: 64,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.bolt_rounded, size: 28),
                  label: Text(
                      _saving ? 'Guardando...' : 'Habilitar Cobro Digital',
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    elevation: 6,
                    shadowColor:
                        AppTheme.primary.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodOption {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool numericOnly;
  const _MethodOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.numericOnly,
  });
}
