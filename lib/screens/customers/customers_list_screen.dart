// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// Pantalla "Mis clientes" (F030). Lista paginada de los clientes del
// tenant con buscador por nombre/teléfono. Cada tarjeta muestra los
// agregados de compra (total gastado, número de compras). Al tocar un
// cliente se abre su detalle (CustomerDetailScreen).
//
// El AppBar incluye un botón "Importar desde Excel/CSV" que abre el
// wizard de 4 pasos del importer F026 (CustomerImportScreen) — no
// duplica código. Al volver del importer la lista se refresca.
//
// Solo es alcanzable cuando la capacidad enable_customer_management
// está ON (el dashboard la gatea — AC-05/AC-07).
//
// Gerontodiseño: textos ≥17pt, filas táctiles, probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/customer.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import 'customer_detail_screen.dart';
import 'customer_import_screen.dart';

class CustomersListScreen extends StatefulWidget {
  /// Inyectable para tests — en producción se usa el ApiService default.
  final ApiService? apiOverride;

  const CustomersListScreen({super.key, this.apiOverride});

  @override
  State<CustomersListScreen> createState() => _CustomersListScreenState();
}

class _CustomersListScreenState extends State<CustomersListScreen> {
  late final ApiService _api;
  final _searchCtrl = TextEditingController();

  List<Customer> _customers = [];
  bool _loading = true;
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _api.listCustomers(query: _query, limit: 200);
      final raw = (res['data'] as List?) ?? const [];
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(Customer.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _customers = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los clientes';
      });
    }
  }

  List<Customer> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openImporter() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerImportScreen()),
    );
    // Al volver del wizard, refrescamos para ver los clientes nuevos.
    await _load();
  }

  Future<void> _openDetail(Customer customer) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerDetailScreen(
          customerId: customer.id,
          customerName: customer.name,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    // El detalle puede no cambiar la lista, pero un refresh barato
    // mantiene los agregados frescos si hubo ventas entremedias.
    await _load();
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
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Mis clientes',
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            key: const Key('customers_import_button'),
            icon: const Icon(Icons.upload_file_rounded,
                color: AppTheme.primary, size: 26),
            tooltip: 'Importar desde Excel/CSV',
            onPressed: _openImporter,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Buscador
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: TextField(
                key: const Key('customers_search'),
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o teléfono',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppTheme.primary, size: 24),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppTheme.warning),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(
                    fontSize: 17, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: const Text('Reintentar',
                  style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
      );
    }
    final results = _filtered;
    if (results.isEmpty) {
      final emptyMsg = _query.trim().isEmpty
          ? 'Aún no tiene clientes registrados.\n'
              'Toque el ícono de importar o registre clientes al cobrar.'
          : 'No se encontraron clientes para "${_query.trim()}".';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline_rounded,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                emptyMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const Key('customers_list'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _CustomerCard(
          customer: results[i],
          onTap: () => _openDetail(results[i]),
        ),
      ),
    );
  }
}

/// Tarjeta de un cliente en la lista — nombre, teléfono y agregados.
class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const _CustomerCard({required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Text(
                  customer.name.isNotEmpty
                      ? customer.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer.phone.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        customer.phone,
                        style: const TextStyle(
                            fontSize: 15, color: AppTheme.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.attach_money_rounded,
                            size: 16, color: AppTheme.success),
                        Text(
                          formatCop(customer.totalSpent),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.success),
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.shopping_bag_outlined,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 2),
                        Text(
                          _purchasesLabel(customer.purchaseCount),
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.primary, size: 26),
            ],
          ),
        ),
      ),
    );
  }

  String _purchasesLabel(int count) =>
      count == 1 ? '1 compra' : '$count compras';
}

/// Formatea un monto en pesos colombianos con separador de miles.
/// Compartido por la lista y el detalle de cliente.
String formatCop(double amount) {
  final cents = amount.round();
  final negative = cents < 0;
  final abs = cents.abs().toString();
  final buffer = StringBuffer(negative ? '-\$' : '\$');
  final start = abs.length % 3;
  if (start > 0) buffer.write(abs.substring(0, start));
  for (int i = start; i < abs.length; i += 3) {
    if (i > 0) buffer.write('.');
    buffer.write(abs.substring(i, i + 3));
  }
  return buffer.toString();
}
