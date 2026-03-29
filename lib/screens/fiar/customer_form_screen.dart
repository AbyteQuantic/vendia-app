import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import 'fiar_controller.dart';

class CustomerFormScreen extends StatefulWidget {
  final FiarController ctrl;

  const CustomerFormScreen({super.key, required this.ctrl});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
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

    final customer = await widget.ctrl.createCustomer(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
    );

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(customer);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text('Cliente ${customer.name} registrado',
                style: const TextStyle(fontSize: 18)),
          ],
        ),
        backgroundColor: AppTheme.success,
        duration: const Duration(seconds: 3),
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
          'Nuevo Cliente',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Formulario de nuevo cliente',
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nombre del cliente',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nameCtrl,
                    style: const TextStyle(fontSize: 20),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Ej: Don Pedro',
                      prefixIcon: Icon(Icons.person_rounded,
                          color: AppTheme.primary, size: 26),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty)
                        return 'Ingrese el nombre';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  const Text('Teléfono',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 20, letterSpacing: 1.5),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    decoration: const InputDecoration(
                      hintText: '310 000 0000',
                      prefixIcon: Icon(Icons.phone_rounded,
                          color: AppTheme.primary, size: 26),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Ingrese el teléfono';
                      if (v.length < 7) return 'Número muy corto';
                      return null;
                    },
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.save_rounded, size: 24),
                    label: Text(_saving ? 'Guardando...' : 'Guardar cliente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
