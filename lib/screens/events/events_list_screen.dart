// Spec: specs/042-modulo-eventos/spec.md
//
// Pantalla "Eventos" (F042). Lista los eventos del organizador con su
// estado, precio y cupo. Botón flotante para crear uno nuevo. Solo es
// alcanzable cuando la capacidad enable_events está ON (el Dashboard la
// gatea — AC-01). Gerontodiseño: textos grandes, filas táctiles, 360dp.

import 'package:flutter/material.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'create_event_screen.dart';

class EventsListScreen extends StatefulWidget {
  /// Inyectable para tests — en producción usa el ApiService default.
  final ApiService? apiOverride;

  const EventsListScreen({super.key, this.apiOverride});

  @override
  State<EventsListScreen> createState() => _EventsListScreenState();
}

class _EventsListScreenState extends State<EventsListScreen> {
  late final ApiService _api;

  List<Event> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final raw = await _api.listEvents();
      final events = raw.map(Event.fromJson).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos cargar sus eventos. Intente de nuevo.';
      });
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<Event>(
      MaterialPageRoute(
        builder: (_) => CreateEventScreen(apiOverride: widget.apiOverride),
      ),
    );
    if (created != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eventos')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('events_create_fab'),
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Crear evento'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _MessageState(
        icon: Icons.wifi_off_rounded,
        message: _error!,
        actionLabel: 'Reintentar',
        onAction: _load,
      );
    }
    if (_events.isEmpty) {
      return _MessageState(
        icon: Icons.event_available_rounded,
        message:
            'Aún no tiene eventos.\nCree su primer curso, conferencia o hackatón.',
        actionLabel: 'Crear evento',
        onAction: _openCreate,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _EventCard(event: _events[i]),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                _StatusBadge(status: event.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${EventType.label(event.type)} · ${EventModality.label(event.modality)}',
              style: const TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.payments_outlined,
                    size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 6),
                Text(
                  event.isFree ? 'Gratis' : '\$${event.price}',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(width: 16),
                Icon(Icons.people_outline,
                    size: 18, color: Colors.grey.shade700),
                const SizedBox(width: 6),
                Text(
                  event.capacity > 0 ? 'Cupo ${event.capacity}' : 'Sin límite',
                  style: const TextStyle(fontSize: 15),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      EventStatus.publicado => Colors.green,
      EventStatus.cancelado => Colors.red,
      EventStatus.archivado => Colors.grey,
      _ => Colors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        EventStatus.label(status),
        style: TextStyle(
            color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _MessageState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
