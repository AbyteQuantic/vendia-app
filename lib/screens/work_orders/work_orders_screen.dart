// Spec: specs/003-trabajos-muebles/spec.md
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/work_order.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'work_order_form_screen.dart';
import 'work_order_widgets.dart';

/// Pantalla de gestión de trabajos de fabricación y reparación de
/// muebles — Feature 003.
///
/// Lista los trabajos del tenant con su cliente, tipo, estado y saldo
/// (AC-01). Permite crear uno nuevo y abrir el detalle, donde se hacen
/// las transiciones, los anticipos y el compartir por WhatsApp.
///
/// Cumple UI_RULES: 3 estados visibles (loading/empty/error), header con
/// máximo 2 acciones laterales, márgenes de 20dp y textos ≥18px.
class WorkOrdersScreen extends StatefulWidget {
  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const WorkOrdersScreen({super.key, this.api});

  @override
  State<WorkOrdersScreen> createState() => _WorkOrdersScreenState();
}

class _WorkOrdersScreenState extends State<WorkOrdersScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  List<WorkOrder> _orders = [];

  /// `customer_id → nombre del cliente` para mostrar en las tarjetas.
  Map<String, String> _customerNames = {};

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rawOrders = await _api.fetchWorkOrders();
      final customersBody = await _api.fetchCustomers(perPage: 200);
      if (!mounted) return;

      final rawCustomers =
          (customersBody['data'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];

      setState(() {
        _orders = rawOrders.map(WorkOrder.fromJson).toList();
        _customerNames = {
          for (final c in rawCustomers)
            (c['id'] ?? c['uuid'] ?? '') as String:
                (c['name'] as String?) ?? 'Cliente',
        };
        _loading = false;
      });
    } catch (e, stack) {
      // El detalle técnico NO se le muestra al usuario (UI_RULES §8),
      // pero JAMÁS se silencia: se registra para diagnóstico
      // (Constitución — nunca tragar errores).
      developer.log(
        'Error al cargar los trabajos',
        name: 'WorkOrdersScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar sus trabajos.';
        _loading = false;
      });
    }
  }

  String _customerName(String customerId) =>
      _customerNames[customerId] ?? 'Cliente';

  Future<void> _openForm({WorkOrder? existing}) async {
    HapticFeedback.lightImpact();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkOrderFormScreen(
          existing: existing,
          api: widget.api,
        ),
      ),
    );
    if (saved == true) {
      await _load();
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
          tooltip: 'Volver',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Trabajos',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
          IconButton(
            key: const Key('btn_add_work_order'),
            icon: const Icon(Icons.add_rounded,
                color: AppTheme.primary, size: 30),
            tooltip: 'Nuevo trabajo',
            onPressed: () => _openForm(),
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
      return WorkOrderErrorState(message: _error!, onRetry: _load);
    }
    if (_orders.isEmpty) {
      return _EmptyState(onAdd: () => _openForm());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _WorkOrderCard(
          order: _orders[i],
          customerName: _customerName(_orders[i].customerId),
          onTap: () => _openForm(existing: _orders[i]),
        ),
      ),
    );
  }
}

/// Tarjeta de un trabajo en la lista.
class _WorkOrderCard extends StatelessWidget {
  final WorkOrder order;
  final String customerName;
  final VoidCallback onTap;

  const _WorkOrderCard({
    required this.order,
    required this.customerName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = workOrderStatusColor(order.status);
    final total = order.total > 0 ? order.total : order.computedTotal;
    final balance = order.balance;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceGrey,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                WorkOrderStatusChip(label: order.statusLabel, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              order.description.isEmpty
                  ? order.typeLabel
                  : '${order.typeLabel} · ${order.description}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Total ${workOrderMoney(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (balance > 0)
                  Flexible(
                    child: Text(
                      'Debe ${workOrderMoney(balance)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.warning,
                      ),
                    ),
                  )
                else
                  const Text(
                    'Pagado',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado vacío con CTA — UI_RULES §8.
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.handyman_rounded,
                size: 72, color: AppTheme.borderColor),
            const SizedBox(height: 16),
            const Text(
              'Aún no tiene trabajos',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Arme una cotización de un mueble con sus materiales y mano '
              'de obra, y siga el trabajo hasta entregarlo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 64,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                label: const Text(
                  'Nuevo trabajo',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
