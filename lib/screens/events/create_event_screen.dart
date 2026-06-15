// Spec: specs/042-modulo-eventos/spec.md
//
// Pantalla "Crear / Editar evento" (F042). El organizador configura su evento:
// nombre, tipo, modalidad, fecha, lugar/enlace, descripción, cupo, precio,
// moneda, métodos de pago y cuotas. Con [existing] entra en modo edición
// (precarga los campos y hace PATCH). Precio múltiplo de $50 en COP. 360dp.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../utils/currency_input.dart';
import '../../utils/event_money.dart';
import 'event_feedback.dart';

class CreateEventScreen extends StatefulWidget {
  /// Inyectable para tests — en producción usa el ApiService default.
  final ApiService? apiOverride;

  /// Cuando viene, la pantalla edita ese evento (PATCH) en vez de crear uno.
  final Event? existing;

  const CreateEventScreen({super.key, this.apiOverride, this.existing});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  late final ApiService _api;
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _priceCtrl = TextEditingController(text: '0');
  final _costCtrl = TextEditingController(text: '0');
  final _capacityCtrl = TextEditingController(text: '0');

  String _type = EventType.curso;
  String _modality = EventModality.presencial;
  String _currency = EventCurrency.cop;
  DateTime? _startAt;
  DateTime? _endAt;
  bool _saving = false;

  // Tasa USD→COP para convertir el precio al cambiar de moneda (fallback).
  double _copPerUsd = 4100;

  // Pago: métodos aceptados (por defecto efectivo + transferencia) y cuotas.
  final Set<String> _methods = {
    EventPaymentMethod.efectivo,
    EventPaymentMethod.transferencia,
  };
  bool _installments = false;
  int _installmentsCount = 2;

  // Datos de pago por método: instrucciones (texto) + QR (URL ya subida).
  final Map<String, TextEditingController> _payInstrCtrls = {
    for (final m in EventPaymentMethod.all) m: TextEditingController(),
  };
  final Map<String, String> _payQrUrls = {};
  String? _qrUploadingMethod;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _loadFxRate();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _locationCtrl.text = e.locationOrLink;
      _cityCtrl.text = e.city;
      _notesCtrl.text = e.locationNotes;
      _priceCtrl.text = CurrencyUtils.formatInt(e.price);
      _costCtrl.text = CurrencyUtils.formatInt(e.cost);
      _capacityCtrl.text = e.capacity.toString();
      _type = e.type;
      _modality = e.modality;
      _currency = EventCurrency.normalize(e.currency);
      _startAt = e.startAt?.toLocal();
      _endAt = e.endAt?.toLocal();
      _installments = e.installmentsEnabled;
      if (e.installmentsCount >= 2) _installmentsCount = e.installmentsCount;
      if (e.enabledPaymentMethods.isNotEmpty) {
        _methods
          ..clear()
          ..addAll(e.enabledPaymentMethods);
      }
      for (final d in e.paymentDetails) {
        _payInstrCtrls[d.method]?.text = d.instructions;
        if (d.qrImageUrl.isNotEmpty) _payQrUrls[d.method] = d.qrImageUrl;
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _cityCtrl.dispose();
    _notesCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _capacityCtrl.dispose();
    for (final c in _payInstrCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Editor opcional del texto del certificado. La IA solo hace el marco; la

  Widget _agentField(TextEditingController c, String label, String hint) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          minLines: 1,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
              labelText: label, hintText: hint, isDense: true),
        ),
      );

  String _fmtDateShort(DateTime? d) => d == null
      ? 'Elegir'
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Asistente IA: pregunta lo esencial del evento, PRE-LLENA el formulario
  /// (ciudad/país, inicio, fin) y redacta la descripción. Todo queda editable.
  /// Si ya hay descripción, la mejora.
  Future<void> _openDescriptionAgent() async {
    if (_titleCtrl.text.trim().length < 2) {
      showEventSnack(context, 'Primero ponle un nombre al evento.',
          kind: EventSnackKind.error);
      return;
    }
    final topic = TextEditingController();
    final audience = TextEditingController();
    final includes = TextEditingController();
    final ciudad = TextEditingController(text: _cityCtrl.text.trim());
    final pais = TextEditingController();
    var startTmp = _startAt;
    var endTmp = _endAt;
    var generating = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final place = [ciudad.text.trim(), pais.text.trim()]
            .where((s) => s.isNotEmpty)
            .join(', ');

        Future<void> generate() async {
          setSheet(() => generating = true);
          try {
            final text = await _api.generateEventDescription(
              title: _titleCtrl.text.trim(),
              type: _type,
              modality: _modality,
              topic: topic.text.trim(),
              audience: audience.text.trim(),
              includes: includes.text.trim(),
              place: place,
              current: _descCtrl.text.trim(),
            );
            if (!mounted) return;
            // Pre-llena el formulario con lo que respondió (editable).
            setState(() {
              _descCtrl.text = text;
              if (place.isNotEmpty) _cityCtrl.text = place;
              if (startTmp != null) _startAt = startTmp;
              if (endTmp != null) _endAt = endTmp;
            });
            if (ctx.mounted) Navigator.pop(ctx);
            showEventSnack(context,
                'Listo: descripción y datos pre-llenados. Revisa y edita.',
                kind: EventSnackKind.success);
          } catch (_) {
            setSheet(() => generating = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('No pudimos generar. Intenta de nuevo.')));
            }
          }
        }

        final hasCurrent = _descCtrl.text.trim().isNotEmpty;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFF6C4CE0)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Asistente del evento',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                    'Respóndeme unas preguntas: pre-lleno los datos y te armo '
                    'una buena descripción. Todo queda editable.',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 14),
                _agentField(topic, '¿De qué trata el evento?',
                    'Ej: técnicas de colorimetría para el tono ámbar'),
                _agentField(audience, '¿Para quién es? (nicho)',
                    'Ej: estilistas y coloristas profesionales'),
                _agentField(includes, '¿Qué incluye o qué aprenderán? (opcional)',
                    'Ej: teoría, práctica y kit de muestras'),
                Row(
                  children: [
                    Expanded(child: _agentField(ciudad, 'Ciudad', 'Ej: Guayaquil')),
                    const SizedBox(width: 10),
                    Expanded(child: _agentField(pais, 'País', 'Ej: Ecuador')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text('Inicio: ${_fmtDateShort(startTmp)}',
                            overflow: TextOverflow.ellipsis),
                        onPressed: () async {
                          final p = await _pickDateTime(
                              current: startTmp, dateHelp: 'Inicio del evento');
                          if (p != null) {
                            setSheet(() {
                              startTmp = p;
                              if (endTmp != null && endTmp!.isBefore(p)) {
                                endTmp = null;
                              }
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event_available_rounded, size: 18),
                        label: Text('Fin: ${_fmtDateShort(endTmp)}',
                            overflow: TextOverflow.ellipsis),
                        onPressed: () async {
                          final p = await _pickDateTime(
                              current: endTmp ?? startTmp,
                              dateHelp: 'Finalización',
                              firstDate: startTmp);
                          if (p != null) setSheet(() => endTmp = p);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('event_desc_ai_generate'),
                    onPressed: generating ? null : generate,
                    icon: generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(generating
                        ? 'Generando…'
                        : (hasCurrent
                            ? 'Mejorar y pre-llenar'
                            : 'Generar y pre-llenar')),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    topic.dispose();
    audience.dispose();
    includes.dispose();
    ciudad.dispose();
    pais.dispose();
  }

  /// Sube el QR de un método y guarda su URL para incluirla al guardar.
  Future<void> _pickPayQr(String method) async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _qrUploadingMethod = method);
    try {
      final url = await _api.uploadEventPaymentQR(picked);
      if (!mounted) return;
      setState(() {
        _payQrUrls[method] = url;
        _qrUploadingMethod = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _qrUploadingMethod = null);
      showEventSnack(context, 'No pudimos subir el QR. Intente con otra imagen.',
          kind: EventSnackKind.error);
    }
  }

  /// Precio actual como entero (el campo lleva separadores de miles).
  int get _priceValue => CurrencyUtils.parseToDouble(_priceCtrl.text).round();

  /// Costo por asistente como entero.
  int get _costValue => CurrencyUtils.parseToDouble(_costCtrl.text).round();

  Future<void> _loadFxRate() async {
    final rate = await _api.fetchUsdCopRate();
    if (rate > 0 && mounted) setState(() => _copPerUsd = rate);
  }

  /// Convierte el precio al cambiar de moneda usando la tasa USD→COP.
  void _convertPrice(String from, String to) {
    final amount = CurrencyUtils.parseToDouble(_priceCtrl.text);
    if (amount <= 0) return;
    double converted;
    if (from == EventCurrency.cop && to == EventCurrency.usd) {
      converted = amount / _copPerUsd;
    } else if (from == EventCurrency.usd && to == EventCurrency.cop) {
      converted = amount * _copPerUsd;
      converted = (converted / 50).round() * 50.0; // múltiplo de $50 (COP)
    } else {
      return;
    }
    _priceCtrl.text = CurrencyUtils.formatInt(converted.round());
  }

  String? _validatePrice(String? raw) {
    final v = CurrencyUtils.parseToDouble(raw).round();
    if (v < 0) return 'Ingrese un precio válido (0 si es gratis)';
    // La regla del múltiplo de $50 es propia del peso colombiano.
    if (_currency == EventCurrency.cop && v % 50 != 0) {
      return 'El precio debe ser múltiplo de \$50';
    }
    return null;
  }

  /// Selector combinado fecha + hora. Devuelve null si el usuario cancela la
  /// fecha. `firstDate` limita hacia atrás; al editar un evento ya pasado se
  /// ajusta para no romper showDatePicker (initialDate < firstDate).
  Future<DateTime?> _pickDateTime({
    required DateTime? current,
    required String dateHelp,
    DateTime? firstDate,
  }) async {
    final now = DateTime.now();
    final base = current ?? now.add(const Duration(days: 7));
    final lower = firstDate ?? now;
    final safeFirst = base.isBefore(lower) ? base : lower;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: safeFirst,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: dateHelp,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? base),
      helpText: 'Hora',
    );
    final t = time ?? TimeOfDay.fromDateTime(current ?? base);
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Future<void> _pickStart() async {
    final picked =
        await _pickDateTime(current: _startAt, dateHelp: 'Inicio del evento');
    if (picked == null) return;
    setState(() {
      _startAt = picked;
      // Si el fin quedó antes del nuevo inicio, lo limpiamos.
      if (_endAt != null && _endAt!.isBefore(picked)) _endAt = null;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDateTime(
      current: _endAt ?? _startAt,
      dateHelp: 'Finalización del evento',
      firstDate: _startAt,
    );
    if (picked == null) return;
    if (_startAt != null && picked.isBefore(_startAt!)) {
      if (mounted) {
        showEventSnack(context,
            'La finalización no puede ser antes del inicio.',
            kind: EventSnackKind.error);
      }
      return;
    }
    setState(() => _endAt = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final price = _priceValue;
      final body = <String, dynamic>{
        'type': _type,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'modality': _modality,
        'location_or_link': _locationCtrl.text.trim(),
        'city': _modality == EventModality.virtual ? '' : _cityCtrl.text.trim(),
        'location_notes':
            _modality == EventModality.virtual ? '' : _notesCtrl.text.trim(),
        'price': price,
        // Costo por asistente (solo eventos de pago) → ganancia = precio − costo.
        'cost': price > 0 ? _costValue : 0,
        'currency': _currency,
        'capacity': int.tryParse(_capacityCtrl.text.trim()) ?? 0,
        // El pago solo aplica a eventos con precio.
        'enabled_payment_methods': price > 0 ? _methods.toList() : <String>[],
        'payment_details': price > 0 ? _buildPaymentDetails() : <Map<String, dynamic>>[],
        'installments_enabled': price > 0 && _installments,
        'installments_count': _installments ? _installmentsCount : 0,
        if (_startAt != null) 'start_at': _startAt!.toUtc().toIso8601String(),
        if (_endAt != null) 'end_at': _endAt!.toUtc().toIso8601String(),
      };
      final result = _isEdit
          ? await _api.updateEvent(widget.existing!.id, body)
          : await _api.createEvent(body);
      if (!mounted) return;
      Navigator.of(context).pop(Event.fromJson(result));
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
      return _isEdit
          ? 'No pudimos guardar los cambios. Intente de nuevo.'
          : 'No pudimos crear el evento. Intente de nuevo.';
    }
    return msg;
  }

  // Configuración de cobro (solo eventos con precio). El cobro ocurre por
  // fuera (VendIA conecta); aquí el organizador declara qué acepta y si
  // permite pagar en cuotas.
  /// Arma payment_details solo con los métodos seleccionados que tengan
  /// instrucciones o QR.
  List<Map<String, dynamic>> _buildPaymentDetails() {
    final out = <Map<String, dynamic>>[];
    for (final m in _methods) {
      final instr = _payInstrCtrls[m]?.text.trim() ?? '';
      final qr = _payQrUrls[m] ?? '';
      if (instr.isNotEmpty || qr.isNotEmpty) {
        out.add({'method': m, 'instructions': instr, 'qr_image_url': qr});
      }
    }
    return out;
  }

  /// Miniatura del QR — soporta data URL (recién subido) o URL http (R2).
  Widget _qrThumb(String url) {
    const size = 52.0;
    if (url.startsWith('data:')) {
      final b64 = url.substring(url.indexOf(',') + 1);
      return Image.memory(base64Decode(b64),
          width: size, height: size, fit: BoxFit.cover);
    }
    return Image.network(url, width: size, height: size, fit: BoxFit.cover);
  }

  /// Bloque por método: instrucciones (número/cuenta) + QR opcional.
  Widget _payMethodDetails(String m) {
    final qr = _payQrUrls[m] ?? '';
    final uploading = _qrUploadingMethod == m;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(EventPaymentMethod.label(m),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            key: Key('pay_instr_$m'),
            controller: _payInstrCtrls[m],
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              hintText:
                  'Datos: número de cuenta, Nequi/Daviplata, a nombre de…',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (qr.isNotEmpty) ...[
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _qrThumb(qr)),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () => setState(() => _payQrUrls.remove(m)),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Quitar QR'),
                ),
              ] else
                OutlinedButton.icon(
                  key: Key('pay_qr_$m'),
                  onPressed: uploading ? null : () => _pickPayQr(m),
                  icon: uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: Text(uploading ? 'Subiendo…' : 'Adjuntar QR de pago'),
                ),
            ],
          ),
        ],
      ),
    );
  }

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
          // Datos de pago por cada método seleccionado (lo verá el asistente
          // para saber a dónde pagar antes de reportar su comprobante).
          if (_methods.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Datos de pago por método',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800)),
            Text('El asistente verá estos datos/QR para pagarte.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            for (final m in EventPaymentMethod.all)
              if (_methods.contains(m)) _payMethodDetails(m),
          ],
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
      _modality == EventModality.virtual ? 'Enlace de la reunión' : 'Dirección';

  String _fmtDateTime(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}  '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String get _startLabel =>
      _startAt == null ? 'Elegir fecha y hora de inicio' : _fmtDateTime(_startAt!);

  String get _endLabel => _endAt == null
      ? 'Elegir fecha y hora de fin (opcional)'
      : _fmtDateTime(_endAt!);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Editar evento' : 'Crear evento')),
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
            // Inicio (fecha + hora)
            InkWell(
              key: const Key('event_date'),
              onTap: _pickStart,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Inicio',
                  suffixIcon: Icon(Icons.event_rounded, size: 20),
                ),
                child: Text(_startLabel,
                    style: TextStyle(
                        fontSize: 16,
                        color: _startAt == null
                            ? Colors.grey.shade600
                            : Colors.black87)),
              ),
            ),
            const SizedBox(height: 16),
            // Finalización (fecha + hora) — opcional. Alimenta el countdown
            // del asistente: en curso entre inicio y fin, finalizado después.
            InkWell(
              key: const Key('event_end_date'),
              onTap: _pickEnd,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Finalización',
                  suffixIcon: Icon(Icons.event_available_rounded, size: 20),
                ),
                child: Text(_endLabel,
                    style: TextStyle(
                        fontSize: 16,
                        color: _endAt == null
                            ? Colors.grey.shade600
                            : Colors.black87)),
              ),
            ),
            const SizedBox(height: 16),
            // Ubicación: enlace (virtual) o dirección+ciudad+indicaciones
            // (presencial/híbrido).
            TextFormField(
              key: const Key('event_location'),
              controller: _locationCtrl,
              textCapitalization: _modality == EventModality.virtual
                  ? TextCapitalization.none
                  : TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _locationLabel,
                hintText: _modality == EventModality.virtual
                    ? 'Ej: https://meet…'
                    : 'Ej: Calle 8 No 28-14',
              ),
            ),
            if (_modality != EventModality.virtual) ...[
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('event_city'),
                controller: _cityCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Ciudad',
                  hintText: 'Ej: Medellín',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('event_location_notes'),
                controller: _notesCtrl,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Indicaciones / edificio',
                  alignLabelWithHint: true,
                  hintText: _modality == EventModality.hibrido
                      ? 'Edificio, piso, cómo llegar… y el enlace virtual.'
                      : 'Edificio, piso, punto de referencia, cómo llegar…',
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Descripción — se muestra en el catálogo (detalle del evento) y
            // alimenta a la IA como contexto. Admite texto largo y estructurado.
            Row(
              children: [
                const Expanded(
                  child: Text('Descripción del evento',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF555555))),
                ),
                TextButton.icon(
                  key: const Key('event_desc_ai'),
                  onPressed: _openDescriptionAgent,
                  icon: const Icon(Icons.auto_awesome_rounded,
                      size: 18, color: Color(0xFF6C4CE0)),
                  label: const Text('Asistente IA',
                      style: TextStyle(
                          color: Color(0xFF6C4CE0),
                          fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 0)),
                ),
              ],
            ),
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
            // Moneda del precio (peso colombiano o dólar).
            SegmentedButton<String>(
              key: const Key('event_currency'),
              segments: const [
                ButtonSegment(value: EventCurrency.cop, label: Text('Peso COP')),
                ButtonSegment(value: EventCurrency.usd, label: Text('Dólar USD')),
              ],
              selected: {_currency},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                final to = s.first;
                if (to != _currency) _convertPrice(_currency, to);
                setState(() {
                  _currency = to;
                  _formKey.currentState?.validate();
                });
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('event_price'),
                    controller: _priceCtrl,
                    decoration: InputDecoration(
                      labelText:
                          'Precio (${_currency == EventCurrency.usd ? 'USD' : 'COP'})',
                      hintText: '0 = gratis',
                      prefixText:
                          _currency == EventCurrency.usd ? 'US\$ ' : '\$ ',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: const [CurrencyInputFormatter()],
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
            // Pago y costo: solo aplican a eventos con precio. Reactivo al campo.
            AnimatedBuilder(
              animation: _priceCtrl,
              builder: (context, _) {
                if (_priceValue <= 0) return const SizedBox(height: 8);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('event_cost'),
                      controller: _costCtrl,
                      decoration: InputDecoration(
                        labelText:
                            'Costo por asistente (${_currency == EventCurrency.usd ? 'USD' : 'COP'})',
                        hintText: 'Lo que te cuesta cada cupo (0 si no tiene)',
                        prefixText:
                            _currency == EventCurrency.usd ? 'US\$ ' : '\$ ',
                        helperText:
                            'Sirve para tu ganancia: se cuenta como venta (precio − costo).',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: const [CurrencyInputFormatter()],
                    ),
                    _paymentConfig(),
                  ],
                );
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
                    : Text(_isEdit ? 'Guardar cambios' : 'Guardar evento',
                        style: const TextStyle(fontSize: 17)),
              ),
            ),
            const SizedBox(height: 12),
            if (!_isEdit)
              Text(
                'Después de guardarlo podrá publicarlo, diseñar la escarapela y '
                'el certificado con IA, y ver a sus inscritos.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
