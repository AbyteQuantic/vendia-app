// Selector de proveedor reutilizable (bottom sheet). Devuelve el proveedor
// elegido como Map {id, company_name, phone, emoji} o null. Lista los
// proveedores del tenant (fetchSuppliers).
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_ui.dart';

Future<Map<String, dynamic>?> showSupplierPicker(BuildContext context,
    {ApiService? api}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SupplierPickerSheet(api: api),
  );
}

class _SupplierPickerSheet extends StatefulWidget {
  final ApiService? api;
  const _SupplierPickerSheet({this.api});

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  late final ApiService _api = widget.api ?? ApiService(AuthService());
  List<Map<String, dynamic>> _suppliers = [];
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
      final list = await _api.fetchSuppliers();
      if (!mounted) return;
      setState(() {
        _suppliers = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los proveedores.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD6D0C8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Elegir proveedor',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
            ),
          ),
          const Divider(height: 16),
          Flexible(child: _body()),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: AppUI.bodySoft, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: _load, child: const Text('Reintentar')),
        ]),
      );
    }
    if (_suppliers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
              'Aún no tiene proveedores. Regístrelos en "Proveedores" para '
              'asignarlos a sus pedidos.',
              textAlign: TextAlign.center,
              style: AppUI.bodySoft),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _suppliers.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 16, endIndent: 12),
      itemBuilder: (_, i) {
        final s = _suppliers[i];
        final name = (s['company_name'] ?? 'Proveedor').toString();
        final emoji = (s['emoji'] ?? '').toString();
        final phone = (s['phone'] ?? '').toString();
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
            child: emoji.isNotEmpty
                ? Text(emoji, style: const TextStyle(fontSize: 20))
                : const Icon(Icons.local_shipping_rounded,
                    color: AppTheme.primary, size: 20),
          ),
          title: Text(name,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          subtitle: phone.isNotEmpty
              ? Text(phone, style: AppUI.bodySoft.copyWith(fontSize: 13))
              : null,
          onTap: () => Navigator.of(context).pop(s),
        );
      },
    );
  }
}
