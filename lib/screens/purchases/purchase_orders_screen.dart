// Spec: specs/002-ordenes-compra/spec.md
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/purchase_order.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'purchase_order_form_screen.dart';

/// Pantalla de gestión de órdenes de compra — Feature 002.
///
/// Lista las PO del tenant con su proveedor, estado y total (AC-01).
/// Permite crear una nueva, abrir el detalle, enviar por WhatsApp (AC-02)
/// y recibir la mercancía (AC-03). El stock NUNCA se ajusta aquí: recibir
/// entra stock vía kardex `purchase_receipt` en el backend (spec §7, D4).
///
/// Cumple UI_RULES: 3 estados visibles (loading/empty/error), header con
/// máximo 2 acciones laterales, márgenes de 20dp y textos ≥18px.
class PurchaseOrdersScreen extends StatefulWidget {
  /// ApiService inyectable para pruebas; en producción usa el default.
  final ApiService? api;

  const PurchaseOrdersScreen({super.key, this.api});

  @override
  State<PurchaseOrdersScreen> createState() => _PurchaseOrdersScreenState();
}

class _PurchaseOrdersScreenState extends State<PurchaseOrdersScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());

  List<PurchaseOrder> _orders = [];

  /// `supplier_id → nombre de la empresa` para mostrar en las tarjetas.
  Map<String, String> _supplierNames = {};

  bool _loading = true;
  String? _error;
  bool _busy = false;

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
      final rawOrders = await _api.fetchPurchaseOrders();
      final rawSuppliers = await _api.fetchSuppliers();
      if (!mounted) return;
      setState(() {
        _orders = rawOrders.map(PurchaseOrder.fromJson).toList();
        _supplierNames = {
          for (final s in rawSuppliers)
            (s['id'] ?? s['uuid'] ?? '') as String:
                (s['company_name'] as String?) ?? 'Proveedor',
        };
        _loading = false;
      });
    } catch (e, stack) {
      // El detalle técnico NO se le muestra al usuario (UI_RULES §8),
      // pero JAMÁS se silencia: se registra para diagnóstico
      // (Constitución — nunca tragar errores).
      developer.log(
        'Error al cargar las órdenes de compra',
        name: 'PurchaseOrdersScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar sus órdenes de compra.';
        _loading = false;
      });
    }
  }

  String _supplierName(String supplierId) =>
      _supplierNames[supplierId] ?? 'Proveedor';

  Future<void> _openForm({PurchaseOrder? existing}) async {
    HapticFeedback.lightImpact();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseOrderFormScreen(
          existing: existing,
          api: widget.api,
        ),
      ),
    );
    if (saved == true) {
      await _load();
      if (!mounted) return;
      _snack('Orden de compra guardada', AppTheme.success);
    }
  }

  /// Envía la PO al proveedor: el backend la pasa a `enviada` y devuelve
  /// la URL `wa.me` con la lista completa de ítems (AC-02).
  Future<void> _send(PurchaseOrder po) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final res = await _api.sendPurchaseOrder(po.uuid);
      final url = res['whatsapp_url'] as String?;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      await _load();
      if (!mounted) return;
      _snack('Pedido enviado al proveedor', AppTheme.success);
    } catch (e, stack) {
      developer.log(
        'Error al enviar la orden ${po.uuid}',
        name: 'PurchaseOrdersScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      _snack('No se pudo enviar el pedido.', AppTheme.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Recibe la PO tras confirmar. El stock entra solo, vía kardex (AC-03).
  Future<void> _receive(PurchaseOrder po) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: const Text(
          'Recibir el pedido',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Al confirmar, el stock de cada producto subirá automáticamente. '
          'Esto no se puede deshacer.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Sí, recibir',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _api.receivePurchaseOrder(po.uuid);
      await _load();
      if (!mounted) return;
      _snack('Pedido recibido. El stock se actualizó.', AppTheme.success);
    } catch (e, stack) {
      developer.log(
        'Error al recibir la orden ${po.uuid}',
        name: 'PurchaseOrdersScreen',
        error: e,
        stackTrace: stack,
      );
      if (!mounted) return;
      _snack('No se pudo recibir el pedido.', AppTheme.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 18)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
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
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Órdenes de compra',
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
            key: const Key('btn_add_purchase_order'),
            icon: const Icon(Icons.add_rounded,
                color: AppTheme.primary, size: 30),
            tooltip: 'Nueva orden',
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
      return _ErrorState(message: _error!, onRetry: _load);
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
        itemBuilder: (_, i) => _PurchaseOrderCard(
          order: _orders[i],
          supplierName: _supplierName(_orders[i].supplierId),
          busy: _busy,
          onTap: () => _openForm(existing: _orders[i]),
          onSend: () => _send(_orders[i]),
          onReceive: () => _receive(_orders[i]),
        ),
      ),
    );
  }
}

/// Color semántico de cada estado del ciclo de vida (DESIGN.md).
Color _statusColor(String status) {
  switch (status) {
    case PurchaseOrder.statusReceived:
      return AppTheme.success;
    case PurchaseOrder.statusCanceled:
      return AppTheme.error;
    case PurchaseOrder.statusSent:
      return AppTheme.primaryLight;
    default:
      return AppTheme.warning;
  }
}

/// Tarjeta de una orden de compra en la lista.
class _PurchaseOrderCard extends StatelessWidget {
  final PurchaseOrder order;
  final String supplierName;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onSend;
  final VoidCallback onReceive;

  const _PurchaseOrderCard({
    required this.order,
    required this.supplierName,
    required this.busy,
    required this.onTap,
    required this.onSend,
    required this.onReceive,
  });

  String _money(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$ $buf';
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(order.status);
    final total = order.total > 0 ? order.total : order.computedTotal;
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
                    supplierName,
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
                _StatusChip(label: order.statusLabel, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${order.items.length} producto'
              '${order.items.length == 1 ? '' : 's'} · ${_money(total)}',
              style: const TextStyle(
                fontSize: 18,
                color: AppTheme.textSecondary,
              ),
            ),
            if (order.canSend || order.canReceive) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  if (order.canSend)
                    Expanded(
                      child: _ActionButton(
                        keyValue: 'btn_send_${order.uuid}',
                        label: 'Enviar',
                        icon: Icons.send_rounded,
                        color: AppTheme.primary,
                        onPressed: busy ? null : onSend,
                      ),
                    ),
                  if (order.canSend && order.canReceive)
                    const SizedBox(width: 12),
                  if (order.canReceive)
                    Expanded(
                      child: _ActionButton(
                        keyValue: 'btn_receive_${order.uuid}',
                        label: 'Recibir',
                        icon: Icons.inventory_2_rounded,
                        color: AppTheme.success,
                        onPressed: busy ? null : onReceive,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Chip de estado con su color semántico.
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Botón de acción dentro de una tarjeta (Enviar / Recibir).
class _ActionButton extends StatelessWidget {
  final String keyValue;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.keyValue,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        key: Key(keyValue),
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 22),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: AppTheme.borderColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
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
            const Icon(Icons.shopping_cart_rounded,
                size: 72, color: AppTheme.borderColor),
            const SizedBox(height: 16),
            const Text(
              'Aún no tiene órdenes de compra',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Arme un pedido con lo que le falta y mándeselo a su '
              'proveedor por WhatsApp.',
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
                  'Nueva orden',
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

/// Estado de error con botón Reintentar — UI_RULES §8.
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 72, color: AppTheme.borderColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 64,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                ),
                child: const Text(
                  'Reintentar',
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
