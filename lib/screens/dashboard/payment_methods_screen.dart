import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  late final ApiService _api;
  List<Map<String, dynamic>> _methods = [];
  bool _loading = true;

  static const _presets = ['Nequi', 'Daviplata', 'Bancolombia', 'Efectivo', 'Tarjeta', 'Otro'];

  @override
  void initState() {
    super.initState();
    _api = ApiService(AuthService());
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await _api.fetchPaymentMethods();
      if (mounted) setState(() { _methods = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _api.deletePaymentMethod(id);
      _fetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _showAddSheet() {
    String? selectedName;
    final detailsCtrl = TextEditingController();

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
            builder: (ctx, setSheetState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6D0C8),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text('Nuevo Método de Pago',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 20),
                // Name dropdown
                DropdownButtonFormField<String>(
                  value: selectedName,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                  decoration: const InputDecoration(
                    labelText: 'Tipo',
                    prefixIcon: Icon(Icons.account_balance_wallet_rounded),
                  ),
                  dropdownColor: Colors.white,
                  items: _presets
                      .map((n) => DropdownMenuItem(
                          value: n,
                          child: Text(n, style: const TextStyle(
                              fontSize: 20, color: Colors.black87))))
                      .toList(),
                  onChanged: (v) => setSheetState(() => selectedName = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: detailsCtrl,
                  style: const TextStyle(fontSize: 20, color: Colors.black87),
                  decoration: const InputDecoration(
                    labelText: 'Número / Detalles',
                    hintText: 'Ej: 300 123 4567',
                    prefixIcon: Icon(Icons.phone_rounded),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (selectedName == null) return;
                      Navigator.of(ctx).pop();
                      try {
                        await _api.createPaymentMethod({
                          'name': selectedName,
                          'account_details': detailsCtrl.text.trim(),
                        });
                        _fetch();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppTheme.error,
                          ));
                        }
                      }
                    },
                    icon: const Icon(Icons.check_rounded, size: 24),
                    label: const Text('Agregar',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String name) => switch (name.toLowerCase()) {
        'nequi' => Icons.phone_android_rounded,
        'daviplata' => Icons.phone_android_rounded,
        'bancolombia' => Icons.account_balance_rounded,
        'tarjeta' => Icons.credit_card_rounded,
        'efectivo' => Icons.payments_rounded,
        _ => Icons.account_balance_wallet_rounded,
      };

  Color _colorFor(String name) => switch (name.toLowerCase()) {
        'nequi' => const Color(0xFF8B5CF6),
        'daviplata' => const Color(0xFFEF4444),
        'bancolombia' => const Color(0xFF3B82F6),
        'tarjeta' => const Color(0xFF10B981),
        'efectivo' => const Color(0xFFF59E0B),
        _ => AppTheme.primary,
      };

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
        title: const Text('Métodos de Pago',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _methods.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_wallet_rounded,
                          size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      const Text('Sin métodos de pago',
                          style: TextStyle(fontSize: 20, color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      const Text('Agregue Nequi, Daviplata u otros',
                          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _methods.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final m = _methods[i];
                    final name = m['name'] as String? ?? '';
                    final details = m['account_details'] as String? ?? '';
                    final color = _colorFor(name);
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(_iconFor(name), color: color, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                                if (details.isNotEmpty)
                                  Text(details, style: const TextStyle(
                                      fontSize: 15, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              HapticFeedback.mediumImpact();
                              _delete(m['id'] as String);
                            },
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: AppTheme.error, size: 24),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF7),
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
            onPressed: _showAddSheet,
            icon: const Icon(Icons.add_rounded, size: 24),
            label: const Text('Agregar Método',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
          ),
        ),
      ),
    );
  }
}
