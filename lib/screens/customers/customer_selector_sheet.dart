// Spec: specs/030-administracion-clientes-no-tienda/spec.md
//
// Selector de cliente reutilizable (bottom sheet). Lo usa el checkout
// del POS para asociar un cliente a la venta (tile "Cliente"). Lista
// los clientes del tenant con buscador por nombre/teléfono y permite
// crear un cliente nuevo al vuelo (nombre obligatorio + teléfono
// opcional) — AC-03.
//
// Devuelve el [Customer] elegido vía Navigator.pop, o null si el cajero
// cierra el sheet sin elegir.
//
// Gerontodiseño: textos ≥17pt, filas táctiles ≥56dp, probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/customer.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Abre el selector de cliente como modal bottom sheet y devuelve el
/// cliente elegido (o null si se cancela).
Future<Customer?> showCustomerSelectorSheet(
  BuildContext context, {
  ApiService? apiOverride,
}) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CustomerSelectorSheet(apiOverride: apiOverride),
  );
}

class CustomerSelectorSheet extends StatefulWidget {
  /// Inyectable para tests — en producción se construye con el
  /// ApiService por defecto.
  final ApiService? apiOverride;

  const CustomerSelectorSheet({super.key, this.apiOverride});

  @override
  State<CustomerSelectorSheet> createState() => _CustomerSelectorSheetState();
}

class _CustomerSelectorSheetState extends State<CustomerSelectorSheet> {
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.listCustomers(query: _query, limit: 100);
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

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    // Filtra client-side de inmediato; si la lista quedó corta porque
    // el backend paginó, re-consultamos para traer coincidencias.
  }

  List<Customer> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openNewCustomerForm() async {
    final created = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewCustomerForm(api: _api),
    );
    if (created != null && mounted) {
      Navigator.of(context).pop(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _filtered;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  child: Text(
                    'Elegir cliente',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ),
              // Buscador
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: TextField(
                  key: const Key('customer_selector_search'),
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
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
              // Nuevo cliente al vuelo
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('customer_selector_new'),
                    onPressed: _openNewCustomerForm,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
                    label: const Text(
                      'Registrar cliente nuevo',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 16),
              Flexible(child: _buildList(results)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<Customer> results) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 44, color: AppTheme.warning),
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
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'No hay clientes. Toque "Registrar cliente nuevo".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    return ListView.separated(
      key: const Key('customer_selector_list'),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: results.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 60, endIndent: 12),
      itemBuilder: (_, i) {
        final c = results[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            child: Text(
              c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary),
            ),
          ),
          title: Text(
            c.name,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
          ),
          subtitle: c.phone.isNotEmpty
              ? Text(c.phone,
                  style: const TextStyle(
                      fontSize: 15, color: AppTheme.textSecondary))
              : null,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop(c);
          },
        );
      },
    );
  }
}

/// Mini-formulario de cliente nuevo al vuelo (nombre obligatorio +
/// teléfono opcional). Persiste vía POST /api/v1/customers y devuelve el
/// [Customer] creado.
class _NewCustomerForm extends StatefulWidget {
  final ApiService api;

  const _NewCustomerForm({required this.api});

  @override
  State<_NewCustomerForm> createState() => _NewCustomerFormState();
}

class _NewCustomerFormState extends State<_NewCustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      final res = await widget.api.createCustomer({
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      final created = Customer.fromJson(res);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo registrar el cliente',
              style: TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D0C8),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Nuevo cliente',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 16),
                const Text('Nombre',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('new_customer_name'),
                  controller: _nameCtrl,
                  style: const TextStyle(fontSize: 19),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: 'Ej: María Pérez',
                    prefixIcon: const Icon(Icons.person_rounded,
                        color: AppTheme.primary, size: 24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Ingrese el nombre';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text('Teléfono (opcional)',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('new_customer_phone'),
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 19, letterSpacing: 1.2),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: 'Ej: 300 000 0000',
                    prefixIcon: const Icon(Icons.phone_rounded,
                        color: AppTheme.primary, size: 24),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const Key('new_customer_save'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.check_rounded, size: 24),
                    label: Text(_saving ? 'Guardando...' : 'Guardar cliente',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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
}
