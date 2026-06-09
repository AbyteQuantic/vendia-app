// Spec: specs/042-modulo-eventos/spec.md
//
// Pantalla "Crear evento" (F042). Formulario simple para que el
// organizador configure su evento desde un menú: título, tipo, modalidad,
// cupo y precio. Camino feliz sin desvíos (Art. I). El precio se valida a
// múltiplo de $50 (Art. VII) — el backend lo reconfirma. Probado en 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';

class CreateEventScreen extends StatefulWidget {
  /// Inyectable para tests — en producción usa el ApiService default.
  final ApiService? apiOverride;

  const CreateEventScreen({super.key, this.apiOverride});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  late final ApiService _api;
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '0');
  final _capacityCtrl = TextEditingController(text: '0');

  String _type = EventType.curso;
  String _modality = EventModality.presencial;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  String? _validatePrice(String? raw) {
    final v = int.tryParse((raw ?? '').trim());
    if (v == null || v < 0) return 'Ingrese un precio válido (0 si es gratis)';
    if (v % 50 != 0) return 'El precio debe ser múltiplo de \$50';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final body = {
        'type': _type,
        'title': _titleCtrl.text.trim(),
        'modality': _modality,
        'price': int.parse(_priceCtrl.text.trim()),
        'capacity': int.parse(_capacityCtrl.text.trim()),
      };
      final created = await _api.createEvent(body);
      if (!mounted) return;
      Navigator.of(context).pop(Event.fromJson(created));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(_friendlyError(e));
    }
  }

  /// Mensaje claro: usa el del backend (AppError trae el `{"error": ...}` en
  /// español) y si no, uno genérico.
  String _friendlyError(Object e) {
    final msg = e is AppError ? e.message : e.toString();
    if (msg.trim().isEmpty || msg.contains('Exception')) {
      return 'No pudimos crear el evento. Intente de nuevo.';
    }
    return msg;
  }

  /// SnackBar de error con buen estilo: flotante, redondeado, rojo, con ícono.
  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear evento')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('event_title'),
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del evento',
                hintText: 'Ej: Curso de repostería',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Escriba un nombre'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('event_type'),
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final t in EventType.all)
                  DropdownMenuItem(value: t, child: Text(EventType.label(t))),
              ],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('event_modality'),
              initialValue: _modality,
              decoration: const InputDecoration(labelText: 'Modalidad'),
              items: [
                for (final m in EventModality.all)
                  DropdownMenuItem(
                      value: m, child: Text(EventModality.label(m))),
              ],
              onChanged: (v) => setState(() => _modality = v ?? _modality),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('event_price'),
              controller: _priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Precio de inscripción (COP)',
                hintText: '0 si es gratis',
                prefixText: '\$ ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: _validatePrice,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('event_capacity'),
              controller: _capacityCtrl,
              decoration: const InputDecoration(
                labelText: 'Cupo máximo',
                hintText: '0 = sin límite',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('event_submit'),
              onPressed: _saving ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Guardar evento',
                        style: TextStyle(fontSize: 17)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
