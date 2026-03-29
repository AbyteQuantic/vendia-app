import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../database/database_service.dart';
import '../../database/sync/sync_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';
import '../../widgets/sync_status_banner.dart';
import 'fiar_controller.dart';
import 'widgets/debtor_card.dart';
import 'customer_form_screen.dart';
import 'credit_detail_screen.dart';

class FiarScreen extends StatefulWidget {
  const FiarScreen({super.key});

  @override
  State<FiarScreen> createState() => _FiarScreenState();
}

class _FiarScreenState extends State<FiarScreen> {
  late final FiarController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = FiarController(
      DatabaseService.instance,
      context.read<SyncService>(),
    );
    _ctrl.loadCustomers();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendWhatsApp(String name, String phone, double balance) async {
    final auth = AuthService();
    final businessName = await auth.getBusinessName() ?? 'mi tienda';
    final message = Uri.encodeComponent(
      '¡Hola $name! 👋\n'
      'Te recuerdo que tienes un saldo pendiente de '
      '${formatCOP(balance)} '
      'en $businessName.\n'
      '¡Gracias por tu preferencia! 🙏',
    );
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final url = 'https://wa.me/57$cleanPhone?text=$message';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Cuentas por Cobrar',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Agregar nuevo cliente',
        child: FloatingActionButton.extended(
          onPressed: () async {
            HapticFeedback.lightImpact();
            await Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => CustomerFormScreen(ctrl: _ctrl)),
            );
          },
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.person_add_rounded, size: 24),
          label: const Text('Nuevo cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      ),
      body: Semantics(
        label: 'Pantalla de cuentas por cobrar',
        child: Column(
          children: [
            const SyncStatusBanner(),
            ListenableBuilder(
              listenable: _ctrl,
              builder: (context, _) {
                return Expanded(
                  child: Column(
                    children: [
                      // Total header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total pendiente',
                              style: TextStyle(
                                fontSize: 18,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            Text(
                              formatCOP(_ctrl.totalPending),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Filters
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterChip(
                                  label: 'Todos',
                                  value: 'all',
                                  selected: _ctrl.filter,
                                  onTap: _ctrl.setFilter),
                              _FilterChip(
                                  label: 'Pendientes',
                                  value: 'pending',
                                  selected: _ctrl.filter,
                                  onTap: _ctrl.setFilter),
                              _FilterChip(
                                  label: 'Parciales',
                                  value: 'partial',
                                  selected: _ctrl.filter,
                                  onTap: _ctrl.setFilter),
                              _FilterChip(
                                  label: 'Pagados',
                                  value: 'paid',
                                  selected: _ctrl.filter,
                                  onTap: _ctrl.setFilter),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Customer list
                      Expanded(
                        child: _ctrl.loading
                            ? const Center(child: CircularProgressIndicator())
                            : _ctrl.customers.isEmpty
                                ? const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.people_outline_rounded,
                                            size: 64,
                                            color: AppTheme.textSecondary),
                                        SizedBox(height: 12),
                                        Text(
                                          'No hay clientes registrados',
                                          style: TextStyle(
                                              fontSize: 18,
                                              color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    itemCount: _ctrl.customers.length,
                                    itemBuilder: (_, i) {
                                      final customer = _ctrl.customers[i];
                                      return DebtorCard(
                                        customer: customer,
                                        onTap: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  CreditDetailScreen(
                                                customer: customer,
                                                ctrl: _ctrl,
                                              ),
                                            ),
                                          );
                                        },
                                        onWhatsApp: () => _sendWhatsApp(
                                          customer.name,
                                          customer.phone,
                                          customer.balance,
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap(value);
        },
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.borderColor,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
