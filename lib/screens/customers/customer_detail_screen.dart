// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// Detalle de un cliente (F030). Muestra:
//   - Header con nombre + teléfono.
//   - Summary cards: total gastado, número de compras, primera y
//     última visita.
//   - Timeline cronológica de ventas; cada venta navega al detalle de
//     venta existente (ReceiptDetailScreen).
//
// Los datos vienen de GET /api/v1/customers/:id/history (AC-06).
//
// Gerontodiseño: textos ≥17pt, summary cards grandes, probado 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/customer.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import '../history/receipt_detail_screen.dart';
import 'customers_list_screen.dart' show formatCop;

class CustomerDetailScreen extends StatefulWidget {
  /// UUID del cliente cuyo historial se va a mostrar.
  final String customerId;

  /// Nombre del cliente — usado para pintar el header de inmediato
  /// mientras el historial carga (evita un header vacío).
  final String customerName;

  /// Inyectable para tests.
  final ApiService? apiOverride;

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.apiOverride,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late final ApiService _api;

  CustomerHistory? _history;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await _api.getCustomerHistory(widget.customerId);
      if (!mounted) return;
      setState(() {
        _history = CustomerHistory.fromJson(res);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el historial';
      });
    }
  }

  void _openSale(CustomerSale sale) {
    HapticFeedback.lightImpact();
    // Pasamos el mapa CRUDO de la venta (incluye `items`, receipt_number, etc.),
    // igual que el historial de ventas normal. Antes se reconstruía un mapa
    // parcial SIN `items` y el detalle mostraba "Sin items registrados".
    final raw = sale.raw.isNotEmpty
        ? sale.raw
        : <String, dynamic>{
            'id': sale.id,
            'uuid': sale.id,
            'total': sale.total,
            'created_at': sale.createdAt?.toIso8601String(),
            'payment_method': sale.paymentMethod,
            'items_count': sale.itemsCount,
          };
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptDetailScreen(sale: raw),
      ),
    );
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
          'Cliente',
          style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
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

    final history = _history!;
    final customer = history.customer;
    final summary = history.summary;
    // Defensive: si el backend no trajo el nombre, usamos el que
    // recibimos por constructor.
    final name = customer.name.isNotEmpty ? customer.name : widget.customerName;
    final sales = history.sales;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _buildHeader(name, customer.phone),
          const SizedBox(height: 20),
          _buildSummaryCards(summary),
          const SizedBox(height: 24),
          const Text(
            'Historial de compras',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),
          _buildTimeline(sales),
        ],
      ),
    );
  }

  Widget _buildHeader(String name, String phone) {
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.14),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone_rounded,
                        size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      phone,
                      style: const TextStyle(
                          fontSize: 17, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(CustomerSummary summary) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.attach_money_rounded,
                color: AppTheme.success,
                label: 'Total gastado',
                value: formatCop(summary.totalSpent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                icon: Icons.shopping_bag_outlined,
                color: AppTheme.primary,
                label: 'Compras',
                value: '${summary.purchaseCount}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                icon: Icons.event_available_rounded,
                color: const Color(0xFF6D28D9),
                label: 'Primera visita',
                value: _formatDate(summary.firstPurchaseAt),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                icon: Icons.update_rounded,
                color: AppTheme.warning,
                label: 'Última visita',
                value: _formatDate(summary.lastPurchaseAt),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeline(List<CustomerSale> sales) {
    if (sales.isEmpty) {
      return Container(
        key: const Key('customer_sales_empty'),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 44, color: Color(0xFF9E9E9E)),
            SizedBox(height: 12),
            Text(
              'Este cliente aún sin compras registradas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 17, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return Column(
      key: const Key('customer_sales_timeline'),
      children: [
        for (final sale in sales) ...[
          _SaleRow(
            sale: sale,
            dateLabel: _formatDateTime(sale.createdAt),
            onTap: () => _openSale(sale),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Tarjeta de resumen — un agregado con ícono, etiqueta y valor.
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _SummaryCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Fila de una venta en la timeline del cliente.
class _SaleRow extends StatelessWidget {
  final CustomerSale sale;
  final String dateLabel;
  final VoidCallback onTap;

  const _SaleRow({
    required this.sale,
    required this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatCop(sale.total),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (sale.itemsCount > 0)
                Text(
                  sale.itemsCount == 1
                      ? '1 artículo'
                      : '${sale.itemsCount} artículos',
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey.shade600),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.primary, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

const _months = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

/// Formatea una fecha como "20 may 2026", o "—" si es null.
String _formatDate(DateTime? date) {
  if (date == null) return '—';
  final local = date.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// Formatea fecha + hora como "20 may, 10:00".
String _formatDateTime(DateTime? date) {
  if (date == null) return '—';
  final local = date.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]}, $hh:$mm';
}
