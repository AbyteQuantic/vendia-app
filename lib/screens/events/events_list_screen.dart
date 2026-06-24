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
import '../../utils/event_money.dart';
import '../../widgets/branch_selector_drawer.dart';
import 'create_event_screen.dart';
import 'event_detail_screen.dart';
import 'event_feedback.dart';
import 'event_ui_kit.dart';

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

  Future<void> _publish(Event e) async {
    try {
      await _api.publishEvent(e.id);
      if (!mounted) return;
      showEventSnack(context, 'Evento publicado en tu catálogo',
          kind: EventSnackKind.success);
      _load();
    } catch (_) {
      if (!mounted) return;
      showEventSnack(context, 'No pudimos publicar el evento.',
          kind: EventSnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(EventUI.s16),
        itemCount: _events.length,
        separatorBuilder: (_, __) => const SizedBox(height: EventUI.s16),
        itemBuilder: (_, i) => _EventCard(
          event: _events[i],
          onPublish: () => _publish(_events[i]),
          onOpen: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EventDetailScreen(
                event: _events[i],
                apiOverride: widget.apiOverride,
              ),
            ));
            _load();
          },
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onPublish;
  final VoidCallback onOpen;
  const _EventCard({
    required this.event,
    required this.onPublish,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // Tarjeta sin borde duro: sombra suave + radius unificado (kit del módulo).
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(EventUI.rCard),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(EventUI.rCard),
          boxShadow: EventUI.shadow,
        ),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(event.title, style: EventUI.title(17))),
                    const SizedBox(width: EventUI.s8),
                    _StatusBadge(status: event.displayStatus),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${EventType.label(event.type)} · ${EventModality.label(event.modality)}',
                  style: EventUI.body(),
                ),
                const SizedBox(height: EventUI.s16),
                Row(
                  children: [
                    const Icon(Icons.payments_outlined,
                        size: 18, color: EventUI.inkSoft),
                    const SizedBox(width: 6),
                    Text(formatEventPrice(event.price, event.currency),
                        style: EventUI.value()),
                    const SizedBox(width: EventUI.s16),
                    const Icon(Icons.people_outline,
                        size: 18, color: EventUI.inkSoft),
                    const SizedBox(width: 6),
                    Text(
                      event.capacity > 0
                          ? 'Cupo ${event.capacity}'
                          : 'Sin límite',
                      style: EventUI.value(),
                    ),
                  ],
                ),
                if (event.status == EventStatus.borrador) ...[
                  const SizedBox(height: EventUI.s16),
                  EventPrimaryButton(
                    key: Key('event_publish_${event.id}'),
                    onPressed: onPublish,
                    icon: Icons.publish_rounded,
                    label: 'Publicar en mi catálogo',
                    height: 48,
                  ),
                ],
              ],
            ),
          ),
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
      EventStatus.publicado => EventUI.success,
      EventStatus.cancelado => EventUI.danger,
      EventStatus.archivado => EventUI.inkSoft,
      EventStatus.finalizado => const Color(0xFF475569),
      _ => EventUI.warning,
    };
    return EventBadge(label: EventStatus.label(status), color: color);
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
            Icon(icon, size: 64, color: EventUI.inkSoft.withValues(alpha: 0.5)),
            const SizedBox(height: EventUI.s16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17, color: EventUI.inkSoft, height: 1.4),
            ),
            const SizedBox(height: EventUI.s24),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: EventUI.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: EventUI.s24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(EventUI.rButton)),
                textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
