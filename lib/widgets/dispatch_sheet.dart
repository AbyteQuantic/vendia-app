// Spec: specs/077-compra-inteligente-insumos/spec.md
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_theme.dart';
import '../utils/format_cop.dart';
import '../theme/app_ui.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

/// Abre el selector de destino para ENVIAR la lista de compra (Spec 077):
/// a un proveedor, un contacto de WhatsApp, un empleado, o solo guardarla como
/// mandado. Crea el mandado (queda registrado → reenviar) y abre WhatsApp.
/// [items]: shopping items; [total]: total estimado. Devuelve true si se envió.
Future<bool?> showDispatchSheet(
    BuildContext context, List<Map<String, dynamic>> items, double total,
    {ApiService? api}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _DispatchSheet(items: items, total: total, api: api),
  );
}

class _DispatchSheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final double total;
  final ApiService? api;
  const _DispatchSheet({required this.items, required this.total, this.api});

  @override
  State<_DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends State<_DispatchSheet> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  String _step = 'menu'; // menu | suppliers | employees | contact
  bool _busy = false;

  List<Map<String, dynamic>> get _lines => widget.items
      .map((it) => {
            'ingredient_id': it['ingredient_id'],
            'name': it['name'],
            'unit': it['unit'],
            'qty': it['shortfall'],
            'unit_price': it['price_per_unit'],
            'cost': it['estimated_cost'],
            'price_source': it['price_source'],
            'is_estimate': it['is_estimate'],
          })
      .toList();

  String _buildMessage() {
    final b = StringBuffer('Buenos días, necesito comprar:\n');
    for (final it in widget.items) {
      final qty = (it['shortfall'] as num?)?.toDouble() ?? 0;
      final q = qty == qty.roundToDouble() ? qty.toStringAsFixed(0) : qty.toStringAsFixed(2);
      b.writeln('• ${it['name']} — $q ${it['unit']}');
    }
    // Solo mostramos el total cuando hay un costo estimado (>0). En pedidos de
    // reposición sin precio de compra conocido, omitirlo evita un "$0" feo.
    if (widget.total > 0) {
      b.writeln('\nTotal aprox: ${formatCOP(widget.total)}');
    }
    return b.toString();
  }

  /// Compartir con el selector NATIVO (elige WhatsApp/contacto/otra app), igual
  /// que compartir el link de la tienda. Guarda el mandado para reenviar.
  Future<void> _shareNative() async {
    setState(() => _busy = true);
    try {
      await _api.createErrand(lines: _lines, assigneeType: 'self', title: 'Compra de insumos');
    } catch (_) {}
    try {
      await Share.share(_buildMessage(), subject: 'Lista de compra');
    } catch (_) {}
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _send({
    required String type,
    String id = '',
    String name = '',
    String phone = '',
  }) async {
    setState(() => _busy = true);
    try {
      final res = await _api.createErrand(
        lines: _lines,
        assigneeType: type,
        assigneeId: id,
        assigneeName: name,
        assigneePhone: phone,
        title: 'Compra de insumos',
      );
      final url = (res['whatsapp_url'] ?? '').toString();
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(url.isNotEmpty ? 'Mandado enviado y guardado.' : 'Mandado guardado en Pendientes.'),
          backgroundColor: AppTheme.success));
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo enviar el mandado.'), backgroundColor: AppTheme.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppUI.s16, right: AppUI.s16, top: AppUI.s16,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppUI.s16,
      ),
      child: _busy
          ? const Padding(padding: EdgeInsets.all(AppUI.s24), child: Center(child: CircularProgressIndicator()))
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_step == 'menu' ? '¿A quién le envía la lista?' : 'Elija',
                  style: AppUI.bodyStrong),
              const SizedBox(height: AppUI.s12),
              if (_step == 'menu') ..._menu(),
              if (_step == 'suppliers') _pickList(_api.fetchSuppliers(),
                  nameKey: 'company_name', phoneKey: 'phone', type: 'supplier', emptyMsg: 'No tiene proveedores guardados.'),
              if (_step == 'employees') _pickList(_api.fetchEmployees(),
                  nameKey: 'name', phoneKey: 'phone', type: 'employee', emptyMsg: 'No tiene empleados registrados.'),
              if (_step == 'contact') _contactForm(),
            ]),
    );
  }

  List<Widget> _menu() {
    Widget tile(String key, IconData icon, String label, String sub, VoidCallback onTap) => InkWell(
          key: Key('dispatch_$key'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Icon(icon, color: AppTheme.primary, size: 22),
              const SizedBox(width: AppUI.s12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppUI.bodyStrong),
                Text(sub, style: AppUI.bodySoft),
              ])),
              const Icon(Icons.chevron_right_rounded, color: AppUI.inkSoft),
            ]),
          ),
        );
    return [
      // Selector NATIVO (elige WhatsApp/contacto/otra app) — como el link de la tienda.
      tile('share', Icons.ios_share_rounded, 'Compartir (elegir app/contacto)', 'Abre el selector para escoger a quién.', _shareNative),
      const Divider(height: 1, color: AppUI.hairline),
      tile('supplier', Icons.local_shipping_rounded, 'Un proveedor', 'De su lista de proveedores.', () => setState(() => _step = 'suppliers')),
      const Divider(height: 1, color: AppUI.hairline),
      tile('contact', Icons.person_add_alt_rounded, 'Un número de WhatsApp', 'Escriba el número directo.', () => setState(() => _step = 'contact')),
      const Divider(height: 1, color: AppUI.hairline),
      tile('employee', Icons.badge_rounded, 'Un empleado', 'Para que haga el mandado.', () => setState(() => _step = 'employees')),
      const Divider(height: 1, color: AppUI.hairline),
      tile('save', Icons.bookmark_added_rounded, 'Solo guardar', 'Queda en Pendientes para después.', () => _send(type: 'self')),
    ];
  }

  Widget _pickList(Future<List<Map<String, dynamic>>> future, {
    required String nameKey, required String phoneKey, required String type, required String emptyMsg,
  }) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (ctx, snap) {
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(AppUI.s16), child: Center(child: CircularProgressIndicator()));
        final list = snap.data!;
        if (list.isEmpty) return Padding(padding: const EdgeInsets.all(AppUI.s8), child: Text(emptyMsg, style: AppUI.bodySoft));
        return Column(mainAxisSize: MainAxisSize.min, children: list.map((e) {
          final name = (e[nameKey] ?? e['name'] ?? '').toString();
          final phone = (e[phoneKey] ?? '').toString();
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(name, style: AppUI.bodyStrong),
            subtitle: phone.isNotEmpty ? Text(phone, style: AppUI.bodySoft) : null,
            trailing: const Icon(Icons.send_rounded, color: AppTheme.primary, size: 20),
            onTap: () => _send(type: type, id: (e['id'] ?? '').toString(), name: name, phone: phone),
          );
        }).toList());
      },
    );
  }

  Widget _contactForm() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre (opcional)')),
      TextField(key: const Key('contact_phone'), controller: phoneCtrl, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Número de WhatsApp')),
      const SizedBox(height: AppUI.s12),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        key: const Key('dispatch_contact_send'),
        onPressed: () {
          final phone = phoneCtrl.text.trim();
          if (phone.length < 7) return;
          _send(type: 'whatsapp_contact', name: nameCtrl.text.trim(), phone: phone);
        },
        icon: const Icon(Icons.chat_rounded, size: 18),
        label: const Text('Enviar por WhatsApp'),
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppUI.radiusSm))),
      )),
    ]);
  }
}
