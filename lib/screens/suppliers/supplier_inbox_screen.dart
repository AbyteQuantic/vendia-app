// Spec: specs/075-proveedores-b2b/spec.md
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/app_error.dart';

/// Buzón del proveedor (Spec 075 F3): pedidos entrantes de las tiendas, con
/// acciones de estado. VendIA solo conecta; el cierre real va por WhatsApp.
class SupplierInboxScreen extends StatefulWidget {
  final ApiService? api;
  const SupplierInboxScreen({super.key, this.api});

  @override
  State<SupplierInboxScreen> createState() => _SupplierInboxScreenState();
}

class _SupplierInboxScreenState extends State<SupplierInboxScreen> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _api.fetchSupplierInbox();
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppError ? e.message : 'No pudimos cargar los pedidos.';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(String orderId, String status) async {
    try {
      await _api.updateSupplierOrderStatus(orderId, status);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo actualizar.'), backgroundColor: AppTheme.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: AppBar(
        backgroundColor: AppUI.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppUI.ink, size: 26),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Pedidos entrantes', style: AppUI.title),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: AppUI.bodySoft))
              : _orders.isEmpty
                  ? const Center(
                      child: Padding(
                      padding: EdgeInsets.all(AppUI.s24),
                      child: Text('Aún no tiene pedidos.\nAparecerán aquí cuando una tienda le pida.',
                          textAlign: TextAlign.center, style: AppUI.bodySoft),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        key: const Key('supplier_inbox_list'),
                        padding: const EdgeInsets.all(AppUI.s16),
                        itemCount: _orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppUI.s8),
                        itemBuilder: (_, i) => _orderCard(_orders[i]),
                      ),
                    ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final status = (o['status'] ?? 'nuevo').toString();
    final id = o['id'].toString();
    List items = const [];
    try {
      items = jsonDecode((o['items'] ?? '[]').toString()) as List;
    } catch (_) {}
    final total = (o['total_amount'] as num?)?.toDouble() ?? 0;
    final delivery = (o['delivery_choice'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: AppUI.card(r: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text((o['buyer_name'] ?? 'Tienda').toString(), style: AppUI.bodyStrong)),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: 4),
          for (final it in items)
            Text('• ${(it['name'] ?? '')} x${it['quantity'] ?? ''}', style: AppUI.bodySoft),
          const SizedBox(height: 4),
          Text('Total aprox: \$${total.toStringAsFixed(0)}  ·  ${_deliveryLabel(delivery)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppUI.ink)),
          if (status == 'nuevo' || status == 'confirmado') ...[
            const SizedBox(height: AppUI.s8),
            Row(children: [
              if (status == 'nuevo')
                _actionBtn('Confirmar', AppTheme.primary, () => _setStatus(id, 'confirmado')),
              if (status == 'confirmado')
                _actionBtn('Entregado', AppTheme.success, () => _setStatus(id, 'entregado')),
              const SizedBox(width: AppUI.s8),
              _actionBtn('Cancelar', AppTheme.error, () => _setStatus(id, 'cancelado'), outline: true),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap, {bool outline = false}) {
    return outline
        ? OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
            child: Text(label))
        : ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white, elevation: 0),
            child: Text(label));
  }

  Widget _statusBadge(String s) {
    final color = s == 'entregado'
        ? AppTheme.success
        : s == 'cancelado'
            ? AppTheme.error
            : s == 'confirmado'
                ? AppTheme.primary
                : AppTheme.warning;
    return MinimalBadge(label: s, color: color);
  }

  String _deliveryLabel(String c) => c == 'proveedor_entrega'
      ? 'El proveedor lleva'
      : c == 'tienda_recoge'
          ? 'La tienda recoge'
          : 'Por acordar';
}
