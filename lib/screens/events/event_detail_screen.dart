// Spec: specs/042-modulo-eventos/spec.md
//
// Detalle del evento + panel de inscritos (F042, T-38/T-39). Muestra los
// datos del evento (incluida la descripción que alimenta a la IA), permite
// publicarlo, diseñar la escarapela/certificado con IA, abrir el escáner de
// check-in/out y ver/gestionar a los inscritos (pago, asistencia, certificado).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/api_config.dart';
import '../../models/customer.dart';
import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../utils/event_money.dart';
import '../../utils/markdown_plain.dart';
import '../promotions/broadcast_list_helper_screen.dart';
import 'create_event_screen.dart';
import 'event_broadcast_screen.dart';
import 'event_badge_designer_screen.dart';
import 'event_certificate_designer_screen.dart';
import 'event_checkin_scan_screen.dart';
import 'event_description_editor.dart';
import 'event_design_screen.dart';
import 'event_feedback.dart';
import 'event_seat_map_sheet.dart';

/// Acento del módulo de Eventos (mismo cian del catálogo / ícono).
const _eventAccent = Color(0xFF0EA5E9);
// Estado de las piezas de diseño: verde = ya generada; ámbar = falta generar.
const _designDone = Color(0xFF059669);
const _designPending = Color(0xFFD97706);

class EventDetailScreen extends StatefulWidget {
  final Event event;
  final ApiService? apiOverride;

  const EventDetailScreen({super.key, required this.event, this.apiOverride});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late final ApiService _api;
  late Event _event;
  List<EventRegistrationView> _regs = [];
  List<EventPaymentView> _pendingPayments = [];
  String? _slug; // slug de la tienda para armar el link del catálogo
  bool _descExpanded = false; // descripción colapsada por defecto
  bool _loading = true;
  bool _issuingAllCerts = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _event = widget.event;
    _loadRegs();
    _loadStore();
  }

  /// Carga el slug del catálogo para armar el link público. Fire-and-forget.
  Future<void> _loadStore() async {
    try {
      final config = await _api.fetchStoreConfig();
      if (!mounted) return;
      setState(() => _slug = (config['store_slug'] as String?)?.trim());
    } catch (_) {/* ignore */}
  }

  Future<void> _loadRegs() async {
    if (mounted) setState(() => _loading = true);
    try {
      final raw = await _api.listEventRegistrations(_event.id);
      // Comprobantes pendientes de revisión (no bloquea si falla).
      List<EventPaymentView> pending = const [];
      try {
        final pays = await _api.listEventPayments(_event.id, status: 'pending');
        pending = pays.map(EventPaymentView.fromJson).toList(growable: false);
      } catch (_) {/* ignore */}
      if (!mounted) return;
      setState(() {
        _regs = raw.map(EventRegistrationView.fromJson).toList(growable: false);
        _pendingPayments = pending;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Abre el mapa de sillas; al volver refresca por si hubo cambios.
  Future<void> _openSeatMap() async {
    HapticFeedback.lightImpact();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventSeatMapSheet(
          eventId: _event.id,
          capacity: _event.capacity,
          registrations: _regs,
        ),
      ),
    );
    if (changed == true) _loadRegs();
  }

  /// Difusión masiva por WhatsApp a los inscritos del evento: arma la Lista de
  /// Difusión (vCard + mensaje) reutilizando el módulo de F033, que ayuda a
  /// administrar envíos dentro del límite gratuito de WhatsApp.
  void _openAttendeeBroadcast() {
    HapticFeedback.lightImpact();
    final withPhone = _regs
        .where((r) => r.customerPhone.trim().isNotEmpty)
        .map((r) => Customer(id: r.id, name: r.customerName, phone: r.customerPhone))
        .toList();
    if (withPhone.isEmpty) {
      _snack('Sus inscritos aún no tienen teléfono para difundir.',
          kind: EventSnackKind.error);
      return;
    }
    final link = _catalogUrl;
    final base =
        '¡Hola! 👋 Le recordamos el evento "${_event.title}". ¡Le esperamos!';
    final message = link == null ? base : '$base\n\nMás info: $link';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BroadcastListHelperScreen(
          customers: withPhone,
          message: message,
        ),
      ),
    );
  }

  /// Envío masivo de certificados a quienes registraron entrada y salida.
  Future<void> _issueAllCertificates() async {
    HapticFeedback.lightImpact();
    setState(() => _issuingAllCerts = true);
    try {
      final n = await _api.issueAllEventCertificates(_event.id);
      if (!mounted) return;
      _snack(
          n == 0
              ? 'No hay asistentes con entrada y salida sin certificado.'
              : 'Certificado emitido a $n asistente${n == 1 ? '' : 's'}. '
                  'Ya pueden verlo en su carné.',
          kind: n == 0 ? EventSnackKind.info : EventSnackKind.success);
      await _loadRegs();
    } catch (_) {
      if (mounted) {
        _snack('No pudimos emitir los certificados. Intenta de nuevo.',
            kind: EventSnackKind.error);
      }
    } finally {
      if (mounted) setState(() => _issuingAllCerts = false);
    }
  }

  Future<void> _approvePayment(EventPaymentView p) async {
    try {
      await _api.approveEventPayment(_event.id, p.id);
      if (!mounted) return;
      _snack('Pago aprobado de ${p.customerName}',
          kind: EventSnackKind.success);
      _loadRegs();
    } catch (_) {
      _snack('No pudimos aprobar el pago.', kind: EventSnackKind.error);
    }
  }

  void _viewProof(EventPaymentView p) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text('Comprobante · ${p.customerName}'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Flexible(
              child: p.proofUrl.startsWith('data:image')
                  ? Image.memory(
                      base64Decode(p.proofUrl.substring(p.proofUrl.indexOf(',') + 1)),
                      fit: BoxFit.contain)
                  : Image.network(p.proofUrl, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish() async {
    try {
      await _api.publishEvent(_event.id);
      if (!mounted) return;
      setState(() => _event = _event.copyWith(status: EventStatus.publicado));
      _snack('Evento publicado en tu catálogo', kind: EventSnackKind.success);
    } catch (_) {
      _snack('No pudimos publicar el evento.', kind: EventSnackKind.error);
    }
  }

  Future<void> _openScanner(String scanType) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventCheckinScanScreen(
          eventId: _event.id,
          scanType: scanType,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    _loadRegs(); // refrescar asistencia al volver
  }

  Future<void> _issueCert(EventRegistrationView r) async {
    try {
      await _api.issueEventCertificate(_event.id, r.id);
      if (!mounted) return;
      _snack('Certificado emitido para ${r.customerName}',
          kind: EventSnackKind.success);
      _loadRegs();
    } catch (_) {
      _snack('No se pudo emitir el certificado.', kind: EventSnackKind.error);
    }
  }

  /// Abre la edición completa del evento (fecha, precio, cupo, moneda, métodos
  /// de pago, cuotas, etc.) reusando la pantalla de crear en modo edición.
  Future<void> _editEvent() async {
    final updated = await Navigator.of(context).push<Event>(
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(
          existing: _event,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _event = updated);
    _snack('Evento actualizado', kind: EventSnackKind.success);
  }

  Future<void> _openDesigner(EventDesignKind kind) async {
    final current = switch (kind) {
      EventDesignKind.poster => _event.posterUrl,
      EventDesignKind.badge => _event.badgeUrl,
      EventDesignKind.certificate => _event.certificateUrl,
    };
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EventDesignScreen(
          eventId: _event.id,
          kind: kind,
          // Precarga la imagen actual (si existe) para verla/modificarla.
          currentImageUrl: current.isEmpty ? null : current,
          // Pre-carga el brief con la descripción para que la IA tenga
          // contexto desde el primer intento.
          initialBrief: _event.description,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    if (url == null || !mounted) return;
    setState(() {
      _event = switch (kind) {
        EventDesignKind.poster => _event.copyWith(posterUrl: url),
        EventDesignKind.badge => _event.copyWith(badgeUrl: url),
        EventDesignKind.certificate => _event.copyWith(certificateUrl: url),
      };
    });
  }

  /// Abre el diseñador WYSIWYG del certificado (fondo IA/subir + firma + logo
  /// + arrastrar/redimensionar elementos). Devuelve el evento actualizado.
  Future<void> _openCertificateDesigner() async {
    HapticFeedback.lightImpact();
    final updated = await Navigator.of(context).push<Event>(
      MaterialPageRoute(
        builder: (_) => EventCertificateDesignerScreen(
          event: _event,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _event = updated);
  }

  /// Abre el diseñador WYSIWYG del CARNÉ/escarapela (mismas opciones que el del
  /// certificado, adaptadas al carné). Devuelve el evento actualizado.
  Future<void> _openBadgeDesigner() async {
    HapticFeedback.lightImpact();
    final updated = await Navigator.of(context).push<Event>(
      MaterialPageRoute(
        builder: (_) => EventBadgeDesignerScreen(
          event: _event,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
    if (updated != null && mounted) setState(() => _event = updated);
  }

  void _snack(String m, {EventSnackKind kind = EventSnackKind.info}) =>
      showEventSnack(context, m, kind: kind);

  @override
  Widget build(BuildContext context) {
    final e = _event;
    final confirmed = _regs.where((r) => r.isConfirmed).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(e.title),
        actions: [
          IconButton(
            key: const Key('detail_edit_event'),
            tooltip: 'Editar evento',
            onPressed: _editEvent,
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRegs,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _HeroHeader(event: e),
            const SizedBox(height: 16),
            _infoCard(e, confirmed),
            const SizedBox(height: 16),
            _descriptionCard(e),
            const SizedBox(height: 16),
            if (e.status == EventStatus.borrador)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('detail_publish'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: _eventAccent,
                  ),
                  onPressed: _publish,
                  icon: const Icon(Icons.publish_rounded),
                  label: const Text('Publicar en mi catálogo',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            const SizedBox(height: 16),
            _aiDesignCard(),
            const SizedBox(height: 16),
            _catalogSection(e),
            const SizedBox(height: 16),
            _attendanceCard(),
            if (_pendingPayments.isNotEmpty) ...[
              const SizedBox(height: 16),
              _paymentsInbox(),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(Icons.groups_rounded, color: _eventAccent),
                const SizedBox(width: 8),
                Text('Inscritos ($confirmed confirmados)',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            if (_regs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('event_seat_map_btn'),
                      onPressed: _openSeatMap,
                      icon: const Icon(Icons.event_seat_rounded, size: 20),
                      label: const Text('Mapa de sillas',
                          style: TextStyle(fontSize: 15)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _eventAccent,
                          side: const BorderSide(color: _eventAccent)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('event_attendee_broadcast_btn'),
                      onPressed: _openAttendeeBroadcast,
                      icon: const Icon(Icons.campaign_rounded, size: 20),
                      label: const Text('Difusión masiva',
                          style: TextStyle(fontSize: 15)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF25D366),
                          side: const BorderSide(color: Color(0xFF25D366))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('event_issue_all_certs_btn'),
                  onPressed: _issuingAllCerts ? null : _issueAllCertificates,
                  icon: _issuingAllCerts
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.workspace_premium_rounded, size: 20),
                  label: Text(_issuingAllCerts
                      ? 'Emitiendo…'
                      : 'Emitir certificados (entrada + salida)'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF059669),
                      side: const BorderSide(color: Color(0xFF059669))),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
            else if (_regs.isEmpty)
              _emptyRegs()
            else
              ..._regs.map(_regTile),
          ],
        ),
      ),
    );
  }

  // ── Tarjeta de datos clave ────────────────────────────────────────────
  Widget _infoCard(Event e, int confirmed) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _infoRow(Icons.category_rounded, 'Tipo',
                '${EventType.label(e.type)} · ${EventModality.label(e.modality)}'),
            if (e.startAt != null) ...[
              const Divider(height: 20),
              _infoRow(Icons.event_rounded, 'Fecha', _formatDate(e.startAt!)),
            ],
            if (e.locationOrLink.trim().isNotEmpty) ...[
              const Divider(height: 20),
              _infoRow(
                e.modality == EventModality.virtual
                    ? Icons.link_rounded
                    : Icons.place_rounded,
                e.modality == EventModality.virtual ? 'Enlace' : 'Dirección',
                e.locationOrLink,
              ),
            ],
            if (e.modality != EventModality.virtual &&
                e.city.trim().isNotEmpty) ...[
              const Divider(height: 20),
              _infoRow(Icons.location_city_rounded, 'Ciudad', e.city),
            ],
            if (e.modality != EventModality.virtual &&
                e.locationNotes.trim().isNotEmpty) ...[
              const Divider(height: 20),
              _infoRow(Icons.info_outline_rounded, 'Indicaciones',
                  e.locationNotes),
            ],
            const Divider(height: 20),
            _infoRow(Icons.payments_rounded, 'Inscripción',
                formatEventPrice(e.price, e.currency)),
            const Divider(height: 20),
            _infoRow(
              Icons.people_rounded,
              'Cupo',
              e.capacity > 0
                  ? '$confirmed / ${e.capacity}'
                  : 'Sin límite ($confirmed inscritos)',
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: _eventAccent),
        const SizedBox(width: 12),
        SizedBox(
          width: 92,
          child: Text(label,
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ── Descripción pública (se muestra en el catálogo + contexto para la IA) ─
  Widget _descriptionCard(Event e) {
    final hasDesc = e.description.trim().isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Descripción para el catálogo',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  key: const Key('detail_edit_description'),
                  onPressed: _editDescription,
                  style: TextButton.styleFrom(
                    foregroundColor: _eventAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(hasDesc ? 'Editar' : 'Agregar'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (hasDesc)
              _collapsibleDescription(e.description)
            else
              Text(
                'Cuente de qué trata: temario, horas, requisitos, a quién va '
                'dirigido… Esto se muestra a sus clientes en el link del '
                'catálogo.',
                style: TextStyle(
                    fontSize: 14, height: 1.4, color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }

  /// Descripción comprimida: muestra unas pocas líneas con degradado y "Ver
  /// más" para no ocupar toda la pantalla. Solo colapsa si el texto es largo.
  Widget _collapsibleDescription(String description) {
    // Umbral: descripciones cortas se muestran completas sin botón.
    final isLong = description.length > 220 || '\n'.allMatches(description).length > 3;
    // Render markdown (negritas, títulos, viñetas) — la descripción admite
    // formato desde el editor.
    final md = MarkdownBody(
      data: description,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 15, height: 1.45, color: Colors.black87),
        h1: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
        h2: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
        listBullet:
            const TextStyle(fontSize: 15, height: 1.45, color: Colors.black87),
        strong: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );

    if (!isLong) return md;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_descExpanded)
          md
        else
          // Colapsada: clip a 120px con degradado de desvanecido. OverflowBox
          // deja que el markdown se mida sin restricción y ClipRect lo recorta.
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.black, Colors.transparent],
              stops: [0.0, 0.75, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: SizedBox(
              height: 120,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: double.infinity,
                  child: md,
                ),
              ),
            ),
          ),
        TextButton(
          onPressed: () => setState(() => _descExpanded = !_descExpanded),
          style: TextButton.styleFrom(
            foregroundColor: _eventAccent,
            padding: const EdgeInsets.symmetric(vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(_descExpanded ? 'Ver menos' : 'Ver más'),
        ),
      ],
    );
  }

  /// Edita la descripción pública en un editor a pantalla completa (mobile).
  /// Envía el evento COMPLETO porque el PATCH del backend reemplaza los campos
  /// enviados (un body parcial borraría fecha/precio/cupo/lugar).
  Future<void> _editDescription() async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            EventDescriptionEditorScreen(initialText: _event.description),
      ),
    );
    if (saved == null) return; // cancelado
    final e = _event;
    final body = <String, dynamic>{
      'type': e.type,
      'title': e.title,
      'description': saved,
      'modality': e.modality,
      'location_or_link': e.locationOrLink,
      'price': e.price,
      'capacity': e.capacity,
      'installments_enabled': e.installmentsEnabled,
      'installments_count': e.installmentsCount,
      if (e.startAt != null) 'start_at': e.startAt!.toUtc().toIso8601String(),
      if (e.endAt != null) 'end_at': e.endAt!.toUtc().toIso8601String(),
    };
    try {
      final updated = await _api.updateEvent(e.id, body);
      if (!mounted) return;
      setState(() => _event = Event.fromJson(updated));
      _snack('Descripción actualizada', kind: EventSnackKind.success);
    } catch (_) {
      _snack('No pudimos guardar la descripción.', kind: EventSnackKind.error);
    }
  }

  // ── Sección destacada: diseñar piezas con IA ──────────────────────────
  Widget _aiDesignCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFE0F2FE)],
        ),
        border: Border.all(color: _eventAccent.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: _eventAccent),
              SizedBox(width: 8),
              Expanded(
                child: Text('Diseñe sus piezas con IA',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'La IA usa el nombre del evento y su descripción; puede regenerar '
            'hasta que le guste.',
            style: TextStyle(fontSize: 14, color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 14),
          // Afiche — pieza principal: es la que aparece en el catálogo y viaja
          // en el link que se comparte por WhatsApp. Verde = ya generado.
          Builder(builder: (_) {
            final done = _event.posterUrl.isNotEmpty;
            return SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('detail_design_poster'),
                style: FilledButton.styleFrom(
                  backgroundColor: done ? _designDone : _eventAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _openDesigner(EventDesignKind.poster),
                icon: Icon(
                    done ? Icons.check_circle_rounded : Icons.campaign_rounded,
                    size: 22),
                label: Text(
                    done
                        ? 'Afiche listo · editar'
                        : 'Generar afiche para el catálogo',
                    style: const TextStyle(fontSize: 16)),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            _event.posterUrl.isNotEmpty
                ? '✓ Generado. Es la imagen del catálogo y del link de WhatsApp; '
                    'tócala para editarla.'
                : '⚠ Falta generarlo. Es la imagen que verán sus clientes en el '
                    'catálogo y en el link de WhatsApp.',
            style: TextStyle(
                fontSize: 12.5,
                color: _event.posterUrl.isNotEmpty
                    ? _designDone
                    : _designPending,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _secondaryDesignButton(
                  const Key('detail_design_badge'),
                  EventDesignKind.badge,
                  'Escarapela',
                  Icons.badge_outlined,
                  _event.badgeUrl.isNotEmpty),
              const SizedBox(width: 12),
              _secondaryDesignButton(
                  const Key('detail_design_cert'),
                  EventDesignKind.certificate,
                  'Certificado',
                  Icons.workspace_premium_outlined,
                  _event.certificateUrl.isNotEmpty),
            ],
          ),
        ],
      ),
    );
  }

  /// Botón secundario (escarapela/certificado) con estado: verde "listo ·
  /// editar" si ya se generó, o acento "falta generar" si aún no.
  Widget _secondaryDesignButton(
      Key key, EventDesignKind kind, String label, IconData icon, bool done) {
    final color = done ? _designDone : _eventAccent;
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: key,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color),
                backgroundColor:
                    done ? _designDone.withValues(alpha: 0.06) : null,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => switch (kind) {
                EventDesignKind.certificate => _openCertificateDesigner(),
                EventDesignKind.badge => _openBadgeDesigner(),
                EventDesignKind.poster => _openDesigner(kind),
              },
              icon: Icon(done ? Icons.check_circle_rounded : icon, size: 20),
              label: Text(label),
            ),
          ),
          const SizedBox(height: 4),
          Text(done ? 'Listo · editar' : 'Falta generar',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: done ? _designDone : _designPending)),
        ],
      ),
    );
  }

  // ── Catálogo en línea + difusión ──────────────────────────────────────
  String? get _catalogUrl =>
      (_slug == null || _slug!.isEmpty) ? null : ApiConfig.publicCatalogUrlFor(_slug!);

  String _shareMessage(Event e) {
    final priceLine = e.isFree ? 'Gratis' : formatEventMoney(e.price, e.currency);
    final url = _catalogUrl;
    return '🎫 ${e.title}\n'
        '${EventType.label(e.type)} · ${EventModality.label(e.modality)}'
        '${e.startAt != null ? ' · ${_formatDate(e.startAt!)}' : ''}\n'
        'Inscripción: $priceLine\n'
        '${e.description.trim().isEmpty ? '' : '\n${markdownToWhatsApp(e.description.trim())}\n'}'
        '${url != null ? '\nInscríbete aquí: $url' : ''}';
  }

  Future<void> _shareEvent(Event e) async {
    await Share.share(_shareMessage(e), subject: e.title);
  }

  void _copyLink() {
    final url = _catalogUrl;
    if (url == null) {
      _snack('Configure el enlace de su tienda en Perfil del negocio.',
          kind: EventSnackKind.info);
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    _snack('Link copiado: $url', kind: EventSnackKind.success);
  }

  void _openDifusion() {
    // La difusión del evento es su propio módulo (no depende de otra
    // capacidad): lista de clientes + redes sociales + un toque por contacto.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EventBroadcastScreen(
        event: _event,
        slug: _slug,
        apiOverride: widget.apiOverride,
      ),
    ));
  }

  Widget _catalogSection(Event e) {
    final published = e.status == EventStatus.publicado;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storefront_rounded, color: _eventAccent),
              SizedBox(width: 8),
              Text('Catálogo y difusión',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            published
                ? 'Así se ve tu evento en el catálogo. Compártelo con tus '
                    'clientes.'
                : 'Publícalo para que aparezca en tu catálogo en línea.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 14),
          _catalogPreview(e),
          const SizedBox(height: 14),
          // Link del catálogo
          if (_catalogUrl != null)
            InkWell(
              onTap: _copyLink,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 18, color: _eventAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          _catalogUrl!.replaceFirst('https://', ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w500)),
                    ),
                    const Icon(Icons.copy_rounded, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Difundir por WhatsApp / redes (acción principal).
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('detail_share_whatsapp'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () => _shareEvent(e),
              icon: const Icon(Icons.share_rounded, size: 20),
              label: const Text('Difundir por WhatsApp',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          // Difusión específica del evento (clientes + redes sociales).
          TextButton.icon(
            key: const Key('detail_open_difusion'),
            onPressed: _openDifusion,
            style: TextButton.styleFrom(foregroundColor: _eventAccent),
            icon: const Icon(Icons.campaign_rounded, size: 18),
            label: const Text('Difusión a mis clientes y redes'),
          ),
        ],
      ),
    );
  }

  /// Mini-tarjeta que espeja cómo se ve el evento en el catálogo público.
  Widget _catalogPreview(Event e) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 180,
            width: double.infinity,
            color: const Color(0xFFF1F5F9),
            child: e.posterUrl.isNotEmpty
                ? (e.posterUrl.startsWith('data:image')
                    ? Image.memory(
                        base64Decode(
                            e.posterUrl.substring(e.posterUrl.indexOf(',') + 1)),
                        fit: BoxFit.contain)
                    : Image.network(e.posterUrl, fit: BoxFit.contain))
                : Container(
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0EA5E9), Color(0xFF1E3A8A)],
                      ),
                    ),
                    child: const Text('🎫', style: TextStyle(fontSize: 40)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  '${EventType.label(e.type)} · ${EventModality.label(e.modality)}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _eventAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(formatEventPrice(e.price, e.currency),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _eventAccent)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bandeja de comprobantes por revisar (pago manual con comprobante) ──
  Widget _paymentsInbox() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFcd34d)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Pagos por revisar (${_pendingPayments.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Comprobantes que enviaron tus asistentes. Apruébalos para activar '
            'su carné.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          ..._pendingPayments.map(_proofTile),
        ],
      ),
    );
  }

  Widget _proofTile(EventPaymentView p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: p.hasProof ? () => _viewProof(p) : null,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                p.hasProof ? Icons.image_rounded : Icons.payments_rounded,
                color: const Color(0xFFD97706),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.customerName.isEmpty ? 'Asistente' : p.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                    'Reportó ${formatEventMoney(p.amount, _event.currency)}${p.note.isEmpty ? '' : ' · ${p.note}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
              ],
            ),
          ),
          if (p.hasProof)
            TextButton(
              onPressed: () => _viewProof(p),
              child: const Text('Ver'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 38),
            ),
            onPressed: () => _approvePayment(p),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }

  // ── Control de asistencia (escáner QR) ────────────────────────────────
  Widget _attendanceCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, color: _eventAccent),
                SizedBox(width: 8),
                Text('Control de asistencia',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            const Text('Escanee el QR de la escarapela en la puerta.',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openScanner(ScanType.checkIn),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Entrada'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openScanner(ScanType.checkOut),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Salida'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyRegs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.person_add_alt_rounded,
              size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          const Text('Aún no hay inscritos.',
              style: TextStyle(color: Colors.black54, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            _event.status == EventStatus.borrador
                ? 'Publique el evento para recibir inscripciones.'
                : 'Comparta su catálogo para que se inscriban.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _regTile(EventRegistrationView r) {
    final attendance = (r.checkedIn ? ' · Entró' : '') +
        (r.checkedOut ? ' · Salió' : '');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _eventAccent.withValues(alpha: 0.12),
                  child: Text(
                    (r.customerName.isEmpty
                            ? 'A'
                            : r.customerName.characters.first)
                        .toUpperCase(),
                    style: const TextStyle(
                        color: _eventAccent, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          r.customerName.isEmpty
                              ? 'Asistente'
                              : r.customerName,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      if (r.customerPhone.isNotEmpty || attendance.isNotEmpty)
                        Text('${r.customerPhone}$attendance',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
                if (r.seatNumber != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _eventAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_seat_rounded,
                            size: 14, color: _eventAccent),
                        const SizedBox(width: 3),
                        Text('${r.seatNumber}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _eventAccent)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _PaymentBadge(reg: r),
              ],
            ),
            // Progreso de pago (solo eventos de pago con saldo pendiente).
            if (r.hasBalance) ...[
              const SizedBox(height: 10),
              _paymentProgress(r),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _recordPayment(r),
                      icon: const Icon(Icons.add_card_rounded, size: 18),
                      label: const Text('Registrar abono'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669)),
                      onPressed: () => _markPaid(r),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Pagado'),
                    ),
                  ),
                ],
              ),
            ],
            // Certificado (cuando es elegible y ya entró).
            if (r.certificateIssued || r.certificateEligible) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: r.certificateIssued
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: Colors.green, size: 18),
                          SizedBox(width: 4),
                          Text('Certificado emitido',
                              style: TextStyle(
                                  color: Colors.green, fontSize: 13)),
                        ],
                      )
                    : TextButton(
                        onPressed: () => _issueCert(r),
                        child: const Text('Emitir certificado'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentProgress(EventRegistrationView r) {
    final pct = r.price > 0 ? (r.amountPaid / r.price).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation(_eventAccent),
          ),
        ),
        const SizedBox(height: 4),
        Text(
            'Pagó ${formatEventMoney(r.amountPaid, _event.currency)} de '
            '${formatEventMoney(r.price, _event.currency)} · faltan '
            '${formatEventMoney(r.balance, _event.currency)}',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        if (r.installments != null) ...[
          const SizedBox(height: 4),
          _installmentSummary(r.installments!),
        ],
      ],
    );
  }

  /// Resumen del cronograma de cuotas del inscrito: cuotas vencidas (rojo),
  /// próxima cuota con su vencimiento y progreso pagadas/total. Lo ve el
  /// organizador para saber a quién recordarle el pago.
  Widget _installmentSummary(EventInstallmentPlan p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.hasOverdue)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: Color(0xFFDC2626)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${p.overdueCount} ${p.overdueCount == 1 ? "cuota vencida" : "cuotas vencidas"} · '
                    '${formatEventMoney(p.overdueAmount, _event.currency)}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        if (p.nextDueDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Próxima cuota: ${formatEventMoney(p.nextDueAmount, _event.currency)} · '
              'vence ${_shortDate(p.nextDueDate!)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Cuotas: ${p.paidCount}/${p.count} pagadas',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  /// Fecha corta en español ("10 jun"), en zona local del dispositivo.
  String _shortDate(DateTime d) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]}';
  }

  /// Registra un abono (cuota). El organizador escribe el monto recibido.
  Future<void> _recordPayment(EventRegistrationView r) async {
    final controller = TextEditingController(text: r.balance.toString());
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar abono'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${r.customerName} debe ${formatEventMoney(r.balance, _event.currency)}.',
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Monto recibido (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text.trim())),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;
    try {
      await _api.recordEventPayment(_event.id, r.id, amount);
      if (!mounted) return;
      _snack('Abono registrado', kind: EventSnackKind.success);
      _loadRegs();
    } catch (_) {
      _snack('No pudimos registrar el abono.', kind: EventSnackKind.error);
    }
  }

  /// Marca la inscripción como pagada en su totalidad (activa el carné).
  Future<void> _markPaid(EventRegistrationView r) async {
    try {
      await _api.confirmEventPayment(_event.id, r.id);
      if (!mounted) return;
      _snack('Pago completo · carné activado', kind: EventSnackKind.success);
      _loadRegs();
    } catch (_) {
      _snack('No pudimos confirmar el pago.', kind: EventSnackKind.error);
    }
  }

  static String _formatDate(DateTime d) {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    final l = d.toLocal();
    final m = months[l.month - 1];
    return '${l.day} de $m de ${l.year}';
  }
}

/// Insignia de estado de pago del inscrito (verde pagado / ámbar pendiente).
class _PaymentBadge extends StatelessWidget {
  final EventRegistrationView reg;
  const _PaymentBadge({required this.reg});

  @override
  Widget build(BuildContext context) {
    final paid = reg.isConfirmed;
    final color = paid ? const Color(0xFF059669) : const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(paid ? Icons.verified_user_rounded : Icons.schedule_rounded,
              size: 14, color: color),
          const SizedBox(width: 4),
          Text(paid ? 'Carné activo' : 'Pago pendiente',
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Encabezado con el título grande y la insignia de estado.
class _HeroHeader extends StatelessWidget {
  final Event event;
  const _HeroHeader({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5E9), Color(0xFF1E3A8A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusChip(status: event.displayStatus),
          const SizedBox(height: 12),
          Text(
            event.title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            '${EventType.label(event.type)} · ${EventModality.label(event.modality)}',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color bg, IconData icon) = switch (status) {
      EventStatus.publicado => (const Color(0xFF059669), Icons.check_circle),
      EventStatus.cancelado => (const Color(0xFFDC2626), Icons.cancel),
      EventStatus.archivado => (Colors.grey, Icons.archive),
      EventStatus.finalizado => (const Color(0xFF475569), Icons.event_available),
      _ => (const Color(0xFFD97706), Icons.edit_note),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: bg),
          const SizedBox(width: 6),
          Text(EventStatus.label(status),
              style: TextStyle(
                  color: bg, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
