// Spec: specs/042-modulo-eventos/spec.md
//
// Detalle del evento + panel de inscritos (F042, T-38/T-39). Muestra los
// datos del evento (incluida la descripción que alimenta a la IA), permite
// publicarlo, diseñar la escarapela/certificado con IA, abrir el escáner de
// check-in/out y ver/gestionar a los inscritos (pago, asistencia, certificado).

import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'event_checkin_scan_screen.dart';
import 'event_design_screen.dart';
import 'event_feedback.dart';

/// Acento del módulo de Eventos (mismo cian del catálogo / ícono).
const _eventAccent = Color(0xFF0EA5E9);

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _event = widget.event;
    _loadRegs();
  }

  Future<void> _loadRegs() async {
    if (mounted) setState(() => _loading = true);
    try {
      final raw = await _api.listEventRegistrations(_event.id);
      if (!mounted) return;
      setState(() {
        _regs = raw.map(EventRegistrationView.fromJson).toList(growable: false);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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

  Future<void> _openDesigner(EventDesignKind kind) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDesignScreen(
          eventId: _event.id,
          kind: kind,
          // Pre-carga el brief con la descripción para que la IA tenga
          // contexto desde el primer intento.
          initialBrief: _event.description,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
  }

  void _snack(String m, {EventSnackKind kind = EventSnackKind.info}) =>
      showEventSnack(context, m, kind: kind);

  @override
  Widget build(BuildContext context) {
    final e = _event;
    final confirmed = _regs.where((r) => r.isConfirmed).length;
    return Scaffold(
      appBar: AppBar(title: Text(e.title)),
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
            _attendanceCard(),
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
                e.modality == EventModality.virtual ? 'Enlace' : 'Lugar',
                e.locationOrLink,
              ),
            ],
            const Divider(height: 20),
            _infoRow(Icons.payments_rounded, 'Inscripción',
                e.isFree ? 'Gratis' : '\$${e.price}'),
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
              Text(e.description,
                  style: const TextStyle(
                      fontSize: 15, height: 1.45, color: Colors.black87))
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

  /// Edita la descripción pública. Envía el evento COMPLETO porque el PATCH
  /// del backend reemplaza los campos enviados (un body parcial borraría
  /// fecha/precio/cupo/lugar).
  Future<void> _editDescription() async {
    final controller = TextEditingController(text: _event.description);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descripción del evento'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 5,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              alignLabelWithHint: true,
              hintText:
                  'De qué trata, qué incluye, duración/horas, temario, '
                  'requisitos previos, a quién va dirigido…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
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
          // en el link que se comparte por WhatsApp.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('detail_design_poster'),
              style: FilledButton.styleFrom(
                backgroundColor: _eventAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => _openDesigner(EventDesignKind.poster),
              icon: const Icon(Icons.campaign_rounded, size: 22),
              label: const Text('Afiche para el catálogo',
                  style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Es la imagen que verán sus clientes en el catálogo y en el link '
            'de WhatsApp.',
            style: TextStyle(fontSize: 12.5, color: Colors.black45),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('detail_design_badge'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _eventAccent,
                    side: const BorderSide(color: _eventAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _openDesigner(EventDesignKind.badge),
                  icon: const Icon(Icons.badge_outlined, size: 20),
                  label: const Text('Escarapela'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('detail_design_cert'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _eventAccent,
                    side: const BorderSide(color: _eventAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _openDesigner(EventDesignKind.certificate),
                  icon: const Icon(Icons.workspace_premium_outlined, size: 20),
                  label: const Text('Certificado'),
                ),
              ),
            ],
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
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _eventAccent.withValues(alpha: 0.12),
          child: Text(
            (r.customerName.isEmpty ? 'A' : r.customerName.characters.first)
                .toUpperCase(),
            style: const TextStyle(
                color: _eventAccent, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(r.customerName.isEmpty ? 'Asistente' : r.customerName,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${r.customerPhone} · ${r.isConfirmed ? "Pagado" : "Pendiente"}'
          '${r.checkedIn ? " · Entró" : ""}${r.checkedOut ? " · Salió" : ""}',
        ),
        trailing: r.certificateIssued
            ? const Icon(Icons.verified, color: Colors.green)
            : (r.certificateEligible
                ? TextButton(
                    onPressed: () => _issueCert(r),
                    child: const Text('Certificar'),
                  )
                : null),
      ),
    );
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
          _StatusChip(status: event.status),
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
