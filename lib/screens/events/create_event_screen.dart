// Spec: specs/042-modulo-eventos/spec.md
//
// Pantalla "Crear evento" (F042). El organizador configura su evento:
// nombre, tipo, modalidad, fecha, lugar/enlace, descripción, cupo y precio.
// La descripción alimenta a la IA que genera la escarapela/certificado y se
// muestra en el catálogo público. Precio múltiplo de $50 (Art. VII). 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import 'event_feedback.dart';

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
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '0');
  final _capacityCtrl = TextEditingController(text: '0');

  String _type = EventType.curso;
  String _modality = EventModality.presencial;
  DateTime? _startAt;
  bool _saving = false;

  // Pago: métodos aceptados (por defecto efectivo + transferencia) y cuotas.
  final Set<String> _methods = {
    EventPaymentMethod.efectivo,
    EventPaymentMethod.transferencia,
  };
  bool _installments = false;
  int _installmentsCount = 2;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startAt ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Fecha del evento',
    );
    if (picked != null) setState(() => _startAt = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final price = int.parse(_priceCtrl.text.trim());
      final body = <String, dynamic>{
        'type': _type,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'modality': _modality,
        'location_or_link': _locationCtrl.text.trim(),
        'price': price,
        'capacity': int.parse(_capacityCtrl.text.trim()),
        // El pago solo aplica a eventos con precio.
        'enabled_payment_methods': price > 0 ? _methods.toList() : <String>[],
        'installments_enabled': price > 0 && _installments,
        'installments_count': _installments ? _installmentsCount : 0,
        if (_startAt != null) 'start_at': _startAt!.toUtc().toIso8601String(),
      };
      final created = await _api.createEvent(body);
      if (!mounted) return;
      Navigator.of(context).pop(Event.fromJson(created));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showEventSnack(context, _friendlyError(e), kind: EventSnackKind.error);
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

  // Configuración de cobro (solo eventos con precio). El cobro ocurre por
  // fuera (VendIA conecta); aquí el organizador declara qué acepta y si
  // permite pagar en cuotas.
  Widget _paymentConfig() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Cómo aceptas el pago?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('Tus asistentes verán estos medios al inscribirse.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in EventPaymentMethod.all)
                FilterChip(
                  label: Text(EventPaymentMethod.label(m)),
                  selected: _methods.contains(m),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _methods.add(m);
                    } else {
                      _methods.remove(m);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Permitir pago en cuotas'),
            subtitle: Text(_installments
                ? 'Hasta $_installmentsCount cuotas — el carné se activa al '
                    'completar el pago.'
                : 'El asistente paga el total de una vez.'),
            value: _installments,
            onChanged: (v) => setState(() => _installments = v),
          ),
          if (_installments)
            Row(
              children: [
                const Text('Número de cuotas:', style: TextStyle(fontSize: 14)),
                const Spacer(),
                IconButton(
                  onPressed: _installmentsCount > 2
                      ? () => setState(() => _installmentsCount--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_installmentsCount',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: _installmentsCount < 12
                      ? () => setState(() => _installmentsCount++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String get _locationLabel =>
      _modality == EventModality.virtual ? 'Enlace de la reunión' : 'Lugar';

  String get _dateLabel => _startAt == null
      ? 'Elegir fecha del evento'
      : '${_startAt!.day.toString().padLeft(2, '0')}/'
          '${_startAt!.month.toString().padLeft(2, '0')}/${_startAt!.year}';

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
                hintText: 'Ej: Curso de tintura ámbar',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Escriba un nombre'
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: const Key('event_type'),
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      for (final t in EventType.all)
                        DropdownMenuItem(
                            value: t, child: Text(EventType.label(t))),
                    ],
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
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
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Fecha
            InkWell(
              key: const Key('event_date'),
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha',
                  suffixIcon: Icon(Icons.calendar_today_rounded, size: 20),
                ),
                child: Text(_dateLabel,
                    style: TextStyle(
                        fontSize: 16,
                        color: _startAt == null
                            ? Colors.grey.shade600
                            : Colors.black87)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('event_location'),
              controller: _locationCtrl,
              decoration: InputDecoration(
                labelText: _locationLabel,
                hintText: _modality == EventModality.virtual
                    ? 'Ej: https://meet…'
                    : 'Ej: Calle 8 No 28-14',
              ),
            ),
            const SizedBox(height: 16),
            // Descripción — se muestra en el catálogo (detalle del evento) y
            // alimenta a la IA como contexto. Admite texto largo y estructurado.
            TextFormField(
              key: const Key('event_description'),
              controller: _descCtrl,
              minLines: 4,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Descripción del evento',
                alignLabelWithHint: true,
                hintText:
                    'Describa el evento para sus clientes: de qué trata, qué '
                    'incluye, a quién va dirigido, duración/horas, temario, '
                    'requisitos previos… Esto se muestra en el link del '
                    'catálogo y le da contexto a la IA para el afiche.',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('event_price'),
                    controller: _priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Precio (COP)',
                      hintText: '0 = gratis',
                      prefixText: '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: _validatePrice,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('event_capacity'),
                    controller: _capacityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cupo',
                      hintText: '0 = sin límite',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            // Pago: solo aplica a eventos con precio. Reactivo al campo precio.
            AnimatedBuilder(
              animation: _priceCtrl,
              builder: (context, _) {
                final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
                if (price <= 0) return const SizedBox(height: 8);
                return _paymentConfig();
              },
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
            const SizedBox(height: 12),
            Text(
              'Después de guardarlo podrá publicarlo, diseñar la escarapela y el '
              'certificado con IA, y ver a sus inscritos.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
