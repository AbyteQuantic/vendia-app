// Spec: specs/042-modulo-eventos/spec.md
//
// Detalle del evento + panel de inscritos (F042, T-38/T-39). Muestra los
// datos del evento (incluida la descripción que alimenta a la IA), permite
// publicarlo, diseñar la escarapela/certificado con IA, abrir el escáner de
// check-in/out y ver/gestionar a los inscritos (pago, asistencia, certificado).

import 'dart:convert';
import 'dart:ui' show ImageFilter;

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
import 'event_ui_kit.dart';

/// Acento del módulo de Eventos (mismo cian del catálogo / ícono).
const _eventAccent = EventUI.accent;
// Verde = pieza de diseño ya generada.
const _designDone = EventUI.success;

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

  // Spec 069 — Finalizar: archiva el evento (sale del catálogo). Los inscritos
  // conservan su carné y certificado.
  Future<void> _finishEvent() async {
    final ok = await _confirmEventAction(
      title: 'Finalizar evento',
      message:
          'El evento dejará de aparecer en su catálogo en línea. Sus inscritos '
          'conservan su carné y certificado. ¿Desea finalizarlo?',
      confirmLabel: 'Finalizar',
    );
    if (ok != true) return;
    try {
      await _api.archiveEvent(_event.id);
      if (!mounted) return;
      setState(() => _event = _event.copyWith(status: EventStatus.archivado));
      _snack('Evento finalizado. Ya no aparece en su catálogo.',
          kind: EventSnackKind.success);
    } catch (_) {
      _snack('No pudimos finalizar el evento.', kind: EventSnackKind.error);
    }
  }

  // Spec 069 — Cancelar: marca el evento cancelado (sale del catálogo). Se
  // ofrece avisar a los inscritos por WhatsApp.
  Future<void> _cancelEvent() async {
    final ok = await _confirmEventAction(
      title: 'Cancelar evento',
      message:
          'El evento se marca como CANCELADO y sale de su catálogo en línea. '
          'Sus inscritos no se borran; avíseles usted mismo. ¿Desea cancelarlo?',
      confirmLabel: 'Cancelar evento',
      danger: true,
    );
    if (ok != true) return;
    try {
      await _api.cancelEvent(_event.id);
      if (!mounted) return;
      setState(() => _event = _event.copyWith(status: EventStatus.cancelado));
      _snack('Evento cancelado. Ya no aparece en su catálogo.',
          kind: EventSnackKind.success);
      // Ofrecer (no forzar) avisar a los inscritos por WhatsApp.
      _openAttendeeBroadcast();
    } catch (_) {
      _snack('No pudimos cancelar el evento.', kind: EventSnackKind.error);
    }
  }

  Future<bool?> _confirmEventAction({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: EventUI.danger)
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
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
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;
    return Scaffold(
      // ── AppBar glass (vidrio esmerilado) ──────────────────────────────
      // El body se extiende DETRÁS del AppBar: al hacer scroll las tarjetas
      // pasan por debajo del título y se difuminan elegantemente tras el
      // vidrio blanco translúcido. Texto oscuro = contraste absoluto.
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AppBar(
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              foregroundColor: EventUI.ink,
              title: Text(e.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: EventUI.ink)),
              actions: [
                IconButton(
                  key: const Key('detail_edit_event'),
                  tooltip: 'Editar evento',
                  onPressed: _editEvent,
                  icon: const Icon(Icons.edit_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRegs,
        edgeOffset: topInset,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, 32),
          children: [
            _HeroHeader(event: e),
            const SizedBox(height: EventUI.s24),
            _infoCard(e, confirmed),
            const SizedBox(height: EventUI.s24),
            _descriptionCard(e),
            if (e.status == EventStatus.borrador) ...[
              const SizedBox(height: EventUI.s24),
              EventPrimaryButton(
                key: const Key('detail_publish'),
                onPressed: _publish,
                icon: Icons.publish_rounded,
                label: 'Publicar en mi catálogo',
              ),
            ],
            const SizedBox(height: EventUI.s24),
            _aiDesignCard(),
            const SizedBox(height: EventUI.s24),
            _catalogSection(e),
            // Spec 069 — Finalizar / Cancelar: solo aplican a un evento que está
            // publicado (en el catálogo). Lo sacan del catálogo en línea.
            if (e.status == EventStatus.publicado) ...[
              const SizedBox(height: EventUI.s24),
              EventSecondaryButton(
                key: const Key('detail_finish_event'),
                onPressed: _finishEvent,
                icon: Icons.flag_rounded,
                label: 'Finalizar evento',
                color: EventUI.inkSoft,
              ),
              const SizedBox(height: EventUI.s8),
              EventSecondaryButton(
                key: const Key('detail_cancel_event'),
                onPressed: _cancelEvent,
                icon: Icons.cancel_rounded,
                label: 'Cancelar evento',
                color: EventUI.danger,
              ),
            ],
            const SizedBox(height: EventUI.s24),
            _attendanceCard(),
            if (_pendingPayments.isNotEmpty) ...[
              const SizedBox(height: EventUI.s24),
              _paymentsInbox(),
            ],
            const SizedBox(height: EventUI.s32),
            Row(
              children: [
                const Icon(Icons.groups_rounded, color: _eventAccent),
                const SizedBox(width: EventUI.s8),
                Expanded(
                  child: Text('Inscritos ($confirmed confirmados)',
                      style: EventUI.title(18)),
                ),
              ],
            ),
            if (_regs.isNotEmpty) ...[
              const SizedBox(height: EventUI.s16),
              Row(
                children: [
                  Expanded(
                    child: EventSecondaryButton(
                      key: const Key('event_seat_map_btn'),
                      onPressed: _openSeatMap,
                      icon: Icons.event_seat_rounded,
                      label: 'Mapa de sillas',
                    ),
                  ),
                  const SizedBox(width: EventUI.s8),
                  Expanded(
                    child: EventSecondaryButton(
                      key: const Key('event_attendee_broadcast_btn'),
                      onPressed: _openAttendeeBroadcast,
                      icon: Icons.campaign_rounded,
                      label: 'Difusión masiva',
                      color: EventUI.whatsapp,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EventUI.s8),
              EventSecondaryButton(
                key: const Key('event_issue_all_certs_btn'),
                onPressed: _issuingAllCerts ? null : _issueAllCertificates,
                busy: _issuingAllCerts,
                icon: Icons.workspace_premium_rounded,
                label: _issuingAllCerts
                    ? 'Emitiendo…'
                    : 'Emitir certificados (entrada + salida)',
                color: EventUI.success,
              ),
            ],
            const SizedBox(height: EventUI.s16),
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
  // Sin divisores duros: la separación entre filas es solo espacio (16px).
  Widget _infoCard(Event e, int confirmed) {
    final rows = <Widget>[
      EventInfoRow(
          icon: Icons.category_rounded,
          label: 'Tipo',
          value:
              '${EventType.label(e.type)} · ${EventModality.label(e.modality)}'),
      if (e.startAt != null)
        EventInfoRow(
            icon: Icons.event_rounded,
            label: 'Fecha',
            value: _formatDate(e.startAt!)),
      if (e.locationOrLink.trim().isNotEmpty)
        EventInfoRow(
          icon: e.modality == EventModality.virtual
              ? Icons.link_rounded
              : Icons.place_rounded,
          label: e.modality == EventModality.virtual ? 'Enlace' : 'Dirección',
          value: e.locationOrLink,
        ),
      if (e.modality != EventModality.virtual && e.city.trim().isNotEmpty)
        EventInfoRow(
            icon: Icons.location_city_rounded, label: 'Ciudad', value: e.city),
      if (e.modality != EventModality.virtual &&
          e.locationNotes.trim().isNotEmpty)
        EventInfoRow(
            icon: Icons.info_outline_rounded,
            label: 'Indicaciones',
            value: e.locationNotes),
      EventInfoRow(
          icon: Icons.payments_rounded,
          label: 'Inscripción',
          value: formatEventPrice(e.price, e.currency)),
      EventInfoRow(
        icon: Icons.people_rounded,
        label: 'Cupo',
        value: e.capacity > 0
            ? '$confirmed / ${e.capacity}'
            : 'Sin límite ($confirmed inscritos)',
      ),
    ];
    return EventCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: EventUI.s16),
            rows[i],
          ],
        ],
      ),
    );
  }

  // ── Descripción pública (se muestra en el catálogo + contexto para la IA) ─
  Widget _descriptionCard(Event e) {
    final hasDesc = e.description.trim().isNotEmpty;
    return EventCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Descripción para el catálogo',
                    style: EventUI.title(15)),
              ),
              EventTertiaryButton(
                key: const Key('detail_edit_description'),
                onPressed: _editDescription,
                icon: Icons.edit_outlined,
                label: hasDesc ? 'Editar' : 'Agregar',
              ),
            ],
          ),
          const SizedBox(height: EventUI.s8),
          if (hasDesc)
            _collapsibleDescription(e.description)
          else
            Text(
              'Cuente de qué trata: temario, horas, requisitos, a quién va '
              'dirigido… Esto se muestra a sus clientes en el link del '
              'catálogo.',
              style: EventUI.body(),
            ),
        ],
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
  // El estado de cada pieza vive EN el botón (color + ícono + label):
  // verde con check = ya generada; acento = falta generar. Sin subtítulos
  // redundantes debajo de los botones.
  Widget _aiDesignCard() {
    final posterDone = _event.posterUrl.isNotEmpty;
    // Fondo blanco estándar, igual que las demás tarjetas (sin pastel).
    return EventCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EventSectionHeader(
            icon: Icons.auto_awesome_rounded,
            title: 'Diseñe sus piezas con IA',
            subtitle: 'La IA usa el nombre del evento y su descripción; '
                'puede regenerar hasta que le guste.',
          ),
          const SizedBox(height: EventUI.s16),
          // Afiche — pieza principal: es la que aparece en el catálogo y viaja
          // en el link que se comparte por WhatsApp.
          EventPrimaryButton(
            key: const Key('detail_design_poster'),
            onPressed: () => _openDesigner(EventDesignKind.poster),
            icon: posterDone
                ? Icons.check_circle_rounded
                : Icons.campaign_rounded,
            label:
                posterDone ? 'Afiche listo' : 'Generar afiche para el catálogo',
            color: posterDone ? _designDone : _eventAccent,
          ),
          const SizedBox(height: EventUI.s8),
          Row(
            children: [
              _designButton(
                  const Key('detail_design_badge'),
                  EventDesignKind.badge,
                  'Escarapela',
                  Icons.badge_outlined,
                  _event.badgeUrl.isNotEmpty),
              const SizedBox(width: EventUI.s8),
              _designButton(
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

  /// Botón secundario (escarapela/certificado) — siempre en el color
  /// primario del módulo (tinte 10% + texto del color); el estado "ya
  /// generada" lo dice solo el ícono de check, sin cambiar de color.
  Widget _designButton(
      Key key, EventDesignKind kind, String label, IconData icon, bool done) {
    return Expanded(
      child: EventSecondaryButton(
        key: key,
        onPressed: () => switch (kind) {
          EventDesignKind.certificate => _openCertificateDesigner(),
          EventDesignKind.badge => _openBadgeDesigner(),
          EventDesignKind.poster => _openDesigner(kind),
        },
        icon: done ? Icons.check_circle_rounded : icon,
        label: label,
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
    return EventCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EventSectionHeader(
            icon: Icons.storefront_rounded,
            title: 'Catálogo y difusión',
            subtitle: published
                ? 'Así se ve tu evento en el catálogo. Compártelo con tus '
                    'clientes.'
                : 'Publícalo para que aparezca en tu catálogo en línea.',
          ),
          const SizedBox(height: EventUI.s16),
          _catalogPreview(e),
          const SizedBox(height: EventUI.s16),
          // Link del catálogo — caja sutil, sin borde duro.
          if (_catalogUrl != null)
            InkWell(
              onTap: _copyLink,
              borderRadius: BorderRadius.circular(EventUI.rButton),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: EventUI.surface,
                  borderRadius: BorderRadius.circular(EventUI.rButton),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link_rounded,
                        size: 18, color: _eventAccent),
                    const SizedBox(width: EventUI.s8),
                    Expanded(
                      child: Text(_catalogUrl!.replaceFirst('https://', ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: EventUI.ink)),
                    ),
                    const Icon(Icons.copy_rounded,
                        size: 16, color: EventUI.inkSoft),
                  ],
                ),
              ),
            ),
          const SizedBox(height: EventUI.s16),
          // Difundir por WhatsApp (acción principal — verde compartir).
          EventPrimaryButton(
            key: const Key('detail_share_whatsapp'),
            onPressed: () => _shareEvent(e),
            icon: Icons.share_rounded,
            label: 'Difundir por WhatsApp',
            color: EventUI.whatsapp,
          ),
          const SizedBox(height: EventUI.s8),
          // Difusión específica del evento (clientes + redes sociales).
          Center(
            child: EventTertiaryButton(
              key: const Key('detail_open_difusion'),
              onPressed: _openDifusion,
              icon: Icons.campaign_rounded,
              label: 'Difusión a mis clientes y redes',
            ),
          ),
        ],
      ),
    );
  }

  /// Mini-tarjeta que espeja cómo se ve el evento en el catálogo público.
  /// Se diferencia del fondo de la tarjeta con un gris súper claro, sin borde.
  Widget _catalogPreview(Event e) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EventUI.rCard),
        color: EventUI.surface,
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
                    style: EventUI.title(15)),
                const SizedBox(height: 2),
                Text(
                  '${EventType.label(e.type)} · ${EventModality.label(e.modality)}',
                  style: EventUI.body(12),
                ),
                const SizedBox(height: EventUI.s8),
                EventBadge(
                    label: formatEventPrice(e.price, e.currency),
                    color: _eventAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bandeja de comprobantes por revisar (pago manual con comprobante) ──
  Widget _paymentsInbox() {
    return EventCard(
      color: const Color(0xFFFFFBEB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EventSectionHeader(
            icon: Icons.receipt_long_rounded,
            color: EventUI.warning,
            title: 'Pagos por revisar (${_pendingPayments.length})',
            subtitle: 'Comprobantes que enviaron tus asistentes. Apruébalos '
                'para activar su carné.',
          ),
          const SizedBox(height: EventUI.s16),
          ..._pendingPayments.map(_proofTile),
        ],
      ),
    );
  }

  Widget _proofTile(EventPaymentView p) {
    return Container(
      margin: const EdgeInsets.only(bottom: EventUI.s8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(EventUI.rButton),
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
                    style: EventUI.value(14.5)),
                Text(
                    'Reportó ${formatEventMoney(p.amount, _event.currency)}${p.note.isEmpty ? '' : ' · ${p.note}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EventUI.body(13)),
              ],
            ),
          ),
          if (p.hasProof)
            EventTertiaryButton(
              onPressed: () => _viewProof(p),
              label: 'Ver',
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: EventUI.success,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(EventUI.rButton)),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            onPressed: () => _approvePayment(p),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
  }

  // ── Control de asistencia (escáner QR) ────────────────────────────────
  // Jerarquía: "Entrada" es LA acción principal al inicio del evento →
  // primary (azul sólido). "Salida" la acompaña como secondary (tinte
  // azul al 10%) — no compiten con el mismo peso visual.
  Widget _attendanceCard() {
    return EventCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EventSectionHeader(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Control de asistencia',
            subtitle: 'Escanee el QR de la escarapela en la puerta.',
          ),
          const SizedBox(height: EventUI.s16),
          Row(
            children: [
              Expanded(
                child: EventPrimaryButton(
                  onPressed: () => _openScanner(ScanType.checkIn),
                  icon: Icons.login_rounded,
                  label: 'Entrada',
                ),
              ),
              const SizedBox(width: EventUI.s8),
              Expanded(
                child: EventSecondaryButton(
                  onPressed: () => _openScanner(ScanType.checkOut),
                  icon: Icons.logout_rounded,
                  label: 'Salida',
                  height: 52, // alineado con el primary de al lado
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyRegs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          vertical: EventUI.s32, horizontal: EventUI.s16),
      decoration: BoxDecoration(
        color: EventUI.surface,
        borderRadius: BorderRadius.circular(EventUI.rCard),
      ),
      child: Column(
        children: [
          const Icon(Icons.person_add_alt_rounded,
              size: 40, color: EventUI.inkSoft),
          const SizedBox(height: EventUI.s8),
          Text('Aún no hay inscritos.', style: EventUI.value()),
          const SizedBox(height: 4),
          Text(
            _event.status == EventStatus.borrador
                ? 'Publique el evento para recibir inscripciones.'
                : 'Comparta su catálogo para que se inscriban.',
            textAlign: TextAlign.center,
            style: EventUI.body(13),
          ),
        ],
      ),
    );
  }

  Widget _regTile(EventRegistrationView r) {
    final attendance = (r.checkedIn ? ' · Entró' : '') +
        (r.checkedOut ? ' · Salió' : '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: EventCard(
        padding: const EdgeInsets.all(EventUI.s16),
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
                        color: _eventAccent, fontWeight: FontWeight.w700),
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
                          style: EventUI.value(14.5)),
                      if (r.customerPhone.isNotEmpty || attendance.isNotEmpty)
                        Text('${r.customerPhone}$attendance',
                            style: EventUI.body(13)),
                    ],
                  ),
                ),
              ],
            ),
            // Badges en su propia línea (Wrap): a 360dp un nombre largo +
            // silla + estado de pago no caben en una sola fila.
            const SizedBox(height: EventUI.s8),
            Wrap(
              spacing: EventUI.s8,
              runSpacing: 4,
              children: [
                if (r.seatNumber != null)
                  EventBadge(
                      label: 'Silla ${r.seatNumber}', color: _eventAccent),
                _PaymentBadge(reg: r),
              ],
            ),
            // Progreso de pago (solo eventos de pago con saldo pendiente).
            if (r.hasBalance) ...[
              const SizedBox(height: EventUI.s16),
              _paymentProgress(r),
              const SizedBox(height: EventUI.s8),
              Row(
                children: [
                  Expanded(
                    child: EventSecondaryButton(
                      onPressed: () => _recordPayment(r),
                      icon: Icons.add_card_rounded,
                      label: 'Registrar abono',
                      height: 44,
                    ),
                  ),
                  const SizedBox(width: EventUI.s8),
                  Expanded(
                    child: EventPrimaryButton(
                      onPressed: () => _markPaid(r),
                      icon: Icons.check_rounded,
                      label: 'Pagado',
                      color: EventUI.success,
                      height: 44,
                    ),
                  ),
                ],
              ),
            ],
            // Certificado (cuando es elegible y ya entró).
            if (r.certificateIssued || r.certificateEligible) ...[
              const SizedBox(height: EventUI.s8),
              Align(
                alignment: Alignment.centerRight,
                child: r.certificateIssued
                    ? const EventBadge(
                        label: 'Certificado emitido', color: EventUI.success)
                    : EventTertiaryButton(
                        onPressed: () => _issueCert(r),
                        label: 'Emitir certificado',
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
            style: EventUI.body(12.5)),
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
              style: EventUI.body(12),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Cuotas: ${p.paidCount}/${p.count} pagadas',
            style: EventUI.body(11.5),
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
/// Píldora semántica sin ícono — el color y el texto ya lo dicen todo.
class _PaymentBadge extends StatelessWidget {
  final EventRegistrationView reg;
  const _PaymentBadge({required this.reg});

  @override
  Widget build(BuildContext context) {
    final paid = reg.isConfirmed;
    return EventBadge(
      label: paid ? 'Carné activo' : 'Pago pendiente',
      color: paid ? EventUI.success : EventUI.warning,
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
      padding: const EdgeInsets.all(EventUI.s24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EventUI.rCard),
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
          const SizedBox(height: EventUI.s16),
          Text(
            event.title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
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
    final Color color = switch (status) {
      EventStatus.publicado => EventUI.success,
      EventStatus.cancelado => EventUI.danger,
      EventStatus.archivado => EventUI.inkSoft,
      EventStatus.finalizado => const Color(0xFF475569),
      _ => EventUI.warning,
    };
    // Píldora blanca sobre el hero — texto semántico contenido (12.5)
    // para que nunca rompa el padding interno del badge.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(EventStatus.label(status),
          style: TextStyle(
              color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }
}
