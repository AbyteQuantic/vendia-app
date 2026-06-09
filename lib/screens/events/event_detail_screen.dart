// Spec: specs/042-modulo-eventos/spec.md
//
// Detalle del evento + panel de inscritos (F042, T-38/T-39). Muestra los
// datos del evento, permite publicarlo, abrir el escáner de check-in/out y
// ver/gestionar a los inscritos (estado de pago, asistencia, certificado).

import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'event_checkin_scan_screen.dart';
import 'event_design_screen.dart';

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
      _snack('Evento publicado en tu catálogo');
    } catch (_) {
      _snack('No pudimos publicar el evento.');
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
      _snack('Certificado emitido para ${r.customerName}');
      _loadRegs();
    } catch (_) {
      _snack('No se pudo emitir el certificado.');
    }
  }

  Future<void> _openDesigner(EventDesignKind kind) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventDesignScreen(
          eventId: _event.id,
          kind: kind,
          apiOverride: widget.apiOverride,
        ),
      ),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final e = _event;
    final confirmed = _regs.where((r) => r.isConfirmed).length;
    return Scaffold(
      appBar: AppBar(title: Text(e.title)),
      body: RefreshIndicator(
        onRefresh: _loadRegs,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _infoCard(e, confirmed),
            const SizedBox(height: 16),
            if (e.status == EventStatus.borrador)
              FilledButton.icon(
                key: const Key('detail_publish'),
                onPressed: _publish,
                icon: const Icon(Icons.publish_rounded),
                label: const Text('Publicar en mi catálogo'),
              ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('detail_design_badge'),
                    onPressed: () => _openDesigner(EventDesignKind.badge),
                    icon: const Icon(Icons.badge_outlined),
                    label: const Text('Escarapela'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('detail_design_cert'),
                    onPressed: () => _openDesigner(EventDesignKind.certificate),
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: const Text('Certificado'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Inscritos ($confirmed confirmados)',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator()))
            else if (_regs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Aún no hay inscritos.',
                    style: TextStyle(color: Colors.black54)),
              )
            else
              ..._regs.map(_regTile),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(Event e, int confirmed) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${EventType.label(e.type)} · ${EventModality.label(e.modality)}',
                style: const TextStyle(fontSize: 15, color: Colors.black54)),
            const SizedBox(height: 8),
            Text(e.isFree ? 'Gratis' : '\$${e.price}',
                style: const TextStyle(fontSize: 16)),
            Text(e.capacity > 0
                ? 'Cupo $confirmed / ${e.capacity}'
                : 'Cupo: sin límite ($confirmed inscritos)'),
            const SizedBox(height: 4),
            Text('Estado: ${EventStatus.label(e.status)}'),
          ],
        ),
      ),
    );
  }

  Widget _regTile(EventRegistrationView r) {
    return Card(
      child: ListTile(
        title: Text(r.customerName.isEmpty ? 'Asistente' : r.customerName),
        subtitle: Text(
          '${r.customerPhone} · ${r.paymentStatus == "confirmed" ? "Pagado" : "Pendiente"}'
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
}
