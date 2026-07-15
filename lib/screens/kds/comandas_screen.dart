// Spec: specs/105-hito-restaurante-comandas/spec.md — F2.
//
// Comandas de Cocina (KDS) — dos pestañas:
//   · Cocina: tickets nuevo/preparando en FIFO con semáforo por tiempo de
//     preparación (MAX duration_min de los ítems), franja "Listos (N)",
//     contador all-day, sonido+flash al llegar pedidos y deshacer de 3 s.
//   · Para entregar: tickets 'listo' con botón ENTREGADO (mesero/cajero).
//
// El chef NUNCA ve dinero (spec §Roles); los totales solo aparecen en la
// pestaña de entrega. Sin conexión se muestra lo último con banner honesto
// (el KDS no es offline-first — riesgo aceptado del concilio).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/order_ticket.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/beep.dart';
import '../../utils/format_cop.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Objetivo por defecto cuando ningún ítem trae duration_min (el tiempo de
/// preparación es opcional desde el día 1 — nunca obligatorio).
const int kDefaultPrepMinutes = 15;

/// Minutos en 'listo' tras los cuales un ticket se resalta como huérfano
/// (auto-alerta del concilio; el backend lo auto-entrega a los 45 si es
/// prepago).
const int kOrphanAlertMinutes = 10;

class ComandasScreen extends StatefulWidget {
  final ApiService? apiOverride;

  /// Intervalo del poll (inyectable en tests). 12 s en producción —
  /// capacidad validada para el free tier (council 2026-06-28).
  final Duration pollInterval;

  const ComandasScreen({
    super.key,
    this.apiOverride,
    this.pollInterval = const Duration(seconds: 12),
  });

  @override
  State<ComandasScreen> createState() => _ComandasScreenState();
}

class _ComandasScreenState extends State<ComandasScreen> {
  late final ApiService _api;

  List<OrderTicket> _tickets = [];
  bool _loading = true;
  bool _firstLoadFailed = false;
  bool _offline = false;
  DateTime? _lastUpdate;

  Timer? _pollTimer;

  /// Ids ya vistos — para detectar pedidos nuevos (sonido + flash).
  final Set<String> _knownIds = {};

  /// Tickets resaltados por ser recién llegados (flash ~2.5 s).
  final Set<String> _flashIds = {};

  /// Transiciones optimistas pendientes de enviar (ventana de deshacer 3 s):
  /// uuid → (estado local aplicado, timer que dispara el PATCH).
  final Map<String, _PendingAdvance> _pending = {};

  /// Envíos de ENTREGADO en vuelo (deshabilita el botón).
  final Set<String> _delivering = {};

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load(initial: true);
    _pollTimer = Timer.periodic(widget.pollInterval, (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // No perder la acción del chef si sale durante la ventana de deshacer:
    // se envía de inmediato (fire-and-forget).
    for (final p in _pending.values) {
      p.timer.cancel();
      unawaited(_api
          .updateOrderStatus(p.uuid, p.newStatus.name)
          .catchError((_) => <String, dynamic>{}));
    }
    _pending.clear();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final rows =
          await _api.fetchOrders(status: 'nuevo,preparando,listo');
      final fetched = rows.map(OrderTicket.fromApi).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)); // FIFO

      // Conservar el estado optimista local mientras el PATCH no salga.
      final merged = fetched
          .map((t) {
            final pend = _pending[t.uuid];
            return pend != null ? t.copyWith(status: pend.newStatus) : t;
          })
          .toList();

      // Pedidos nuevos → sonido + flash (no en la primera carga).
      final incoming = merged
          .where((t) =>
              t.status == OrderStatus.nuevo && !_knownIds.contains(t.uuid))
          .map((t) => t.uuid)
          .toList();
      if (incoming.isNotEmpty && _knownIds.isNotEmpty) {
        unawaited(playBeep().catchError((_) {}));
        _flashIds.addAll(incoming);
        Timer(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _flashIds.removeAll(incoming));
        });
      }
      _knownIds.addAll(merged.map((t) => t.uuid));

      if (!mounted) return;
      setState(() {
        _tickets = merged;
        _loading = false;
        _firstLoadFailed = false;
        _offline = false;
        _lastUpdate = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (initial && _tickets.isEmpty) _firstLoadFailed = true;
        _loading = false;
        _offline = true;
      });
    }
  }

  // ── Transición optimista con deshacer de 3 s ─────────────────────────────

  void _advance(OrderTicket ticket) {
    final next = ticket.status == OrderStatus.nuevo
        ? OrderStatus.preparando
        : OrderStatus.listo;
    HapticFeedback.mediumImpact();

    final timer = Timer(const Duration(seconds: 3), () => _commit(ticket.uuid));
    _pending[ticket.uuid] =
        _PendingAdvance(uuid: ticket.uuid, newStatus: next, timer: timer);

    setState(() {
      _tickets = _tickets
          .map((t) => t.uuid == ticket.uuid ? t.copyWith(status: next) : t)
          .toList();
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next == OrderStatus.preparando
            ? '${ticket.label} en preparación'
            : '${ticket.label} listo para entregar'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'DESHACER',
          onPressed: () => _undo(ticket.uuid, ticket.status),
        ),
      ),
    );
  }

  void _undo(String uuid, OrderStatus previous) {
    final pend = _pending.remove(uuid);
    if (pend == null) return; // ya se envió
    pend.timer.cancel();
    if (!mounted) return;
    setState(() {
      _tickets = _tickets
          .map((t) => t.uuid == uuid ? t.copyWith(status: previous) : t)
          .toList();
    });
  }

  Future<void> _commit(String uuid) async {
    final pend = _pending.remove(uuid);
    if (pend == null) return;
    try {
      await _api.updateOrderStatus(uuid, pend.newStatus.name);
    } catch (_) {
      if (!mounted) return;
      // Revertir: el servidor sigue siendo la verdad.
      setState(() {
        _tickets = _tickets
            .map((t) => t.uuid == uuid
                ? t.copyWith(
                    status: pend.newStatus == OrderStatus.preparando
                        ? OrderStatus.nuevo
                        : OrderStatus.preparando)
                : t)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar el pedido. Revise la conexión.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _markDelivered(OrderTicket ticket) async {
    HapticFeedback.mediumImpact();
    setState(() => _delivering.add(ticket.uuid));
    try {
      await _api.updateOrderStatus(ticket.uuid, OrderStatus.entregado.name);
      if (!mounted) return;
      setState(() {
        _tickets = _tickets.where((t) => t.uuid != ticket.uuid).toList();
        _delivering.remove(ticket.uuid);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ticket.label} entregado ✓'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _delivering.remove(ticket.uuid));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo marcar la entrega. Intente de nuevo.'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Derivados ─────────────────────────────────────────────────────────────

  List<OrderTicket> get _enCocina => _tickets
      .where((t) =>
          t.status == OrderStatus.nuevo || t.status == OrderStatus.preparando)
      .toList();

  List<OrderTicket> get _listos =>
      _tickets.where((t) => t.status == OrderStatus.listo).toList();

  /// Contador "all day": cuánto hay que producir de cada producto sumando
  /// todos los tickets activos en cocina (el chef cocina en tandas).
  Map<String, int> get _allDay {
    final map = <String, int>{};
    for (final t in _enCocina) {
      for (final it in t.items) {
        map[it.productName] = (map[it.productName] ?? 0) + it.quantity;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppUI.pageBg,
        appBar: glassAppBar(
          title: 'Comandas',
          onBack: () => Navigator.of(context).pop(),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: AppUI.s8),
              child: Center(child: BranchSelectorChip()),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_offline) _offlineBanner(),
            _tabs(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _firstLoadFailed
                      ? _errorState()
                      : TabBarView(
                          children: [_cocinaTab(), _entregarTab()],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    return Container(
      color: Colors.white,
      child: TabBar(
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppUI.inkSoft,
        indicatorColor: AppTheme.primary,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: [
          Tab(text: 'Cocina (${_enCocina.length})'),
          Tab(text: 'Para entregar (${_listos.length})'),
        ],
      ),
    );
  }

  Widget _offlineBanner() {
    final hhmm = _lastUpdate == null
        ? ''
        : ' (${_lastUpdate!.hour.toString().padLeft(2, '0')}:${_lastUpdate!.minute.toString().padLeft(2, '0')})';
    return Container(
      width: double.infinity,
      color: AppTheme.warning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(
          horizontal: AppUI.s16, vertical: AppUI.s8),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, size: 16, color: Color(0xFFB45309)),
          const SizedBox(width: AppUI.s8),
          Expanded(
            child: Text(
              'Sin conexión — mostrando lo último$hhmm',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Color(0xFFB45309)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppUI.inkSoft),
            const SizedBox(height: AppUI.s16),
            const Text('No se pudieron cargar las comandas.',
                style: AppUI.bodyStrong, textAlign: TextAlign.center),
            const SizedBox(height: AppUI.s16),
            AppButton(
              label: 'Reintentar',
              expand: false,
              onPressed: () {
                setState(() {
                  _loading = true;
                  _firstLoadFailed = false;
                });
                _load(initial: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Pestaña Cocina ────────────────────────────────────────────────────────

  Widget _cocinaTab() {
    final enCocina = _enCocina;
    if (enCocina.isEmpty && _listos.isEmpty) {
      return _emptyState(
        icon: Icons.soup_kitchen_rounded,
        title: 'No hay pedidos en cocina',
        subtitle:
            'Los pedidos de mesas y mostrador aparecen aquí apenas se registran.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppUI.s16),
        children: [
          if (_listos.isNotEmpty) ...[
            _listosStrip(),
            const SizedBox(height: AppUI.s12),
          ],
          if (_allDay.isNotEmpty) ...[
            _allDayStrip(),
            const SizedBox(height: AppUI.s12),
          ],
          for (final t in enCocina) _cocinaCard(t),
          const SizedBox(height: AppUI.s24),
        ],
      ),
    );
  }

  /// Franja "Listos (N)" — el chef ve qué está esperando recogida sin
  /// cambiar de pestaña. Rojo si lleva >10 min huérfano.
  Widget _listosStrip() {
    return SoftCard(
      padding: const EdgeInsets.all(AppUI.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LISTOS ESPERANDO ENTREGA (${_listos.length})',
              style: AppUI.sectionLabel),
          const SizedBox(height: AppUI.s8),
          Wrap(
            spacing: AppUI.s8,
            runSpacing: AppUI.s8,
            children: [
              for (final t in _listos)
                MinimalBadge(
                  label:
                      '${t.label} · ${_minutesSince(t.listoAt ?? t.createdAt)} min',
                  color: _minutesSince(t.listoAt ?? t.createdAt) >=
                          kOrphanAlertMinutes
                      ? AppTheme.error
                      : AppTheme.success,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Contador all-day: "3× Empanada · 2× Hamburguesa".
  Widget _allDayStrip() {
    final entries = _allDay.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SoftCard(
      padding: const EdgeInsets.all(AppUI.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TODO EL DÍA (POR PREPARAR)', style: AppUI.sectionLabel),
          const SizedBox(height: AppUI.s8),
          Wrap(
            spacing: AppUI.s8,
            runSpacing: AppUI.s8,
            children: [
              for (final e in entries)
                MinimalBadge(
                    label: '${e.value}× ${e.key}', color: AppTheme.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cocinaCard(OrderTicket t) {
    final minutes = _minutesSince(t.createdAt);
    final goal = t.maxDurationMin ?? kDefaultPrepMinutes;
    final Color semaforo = minutes < goal
        ? AppTheme.success
        : (minutes < goal + 10 ? AppTheme.warning : AppTheme.error);
    final flashing = _flashIds.contains(t.uuid);
    final isNuevo = t.status == OrderStatus.nuevo;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.only(bottom: AppUI.s12),
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: BoxDecoration(
        color: flashing
            ? AppTheme.primary.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(AppUI.radius),
        boxShadow: AppUI.shadow,
        border: Border(
          left: BorderSide(color: semaforo, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.title),
              ),
              const SizedBox(width: AppUI.s8),
              MinimalBadge(
                label: '$minutes min · meta ~$goal',
                color: semaforo,
              ),
            ],
          ),
          if ((t.customerName ?? '').isNotEmpty ||
              t.type == OrderType.paraLlevar) ...[
            const SizedBox(height: AppUI.s4),
            Text(
              [
                if ((t.customerName ?? '').isNotEmpty) t.customerName!,
                if (t.type == OrderType.paraLlevar) 'Para llevar',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppUI.bodySoft,
            ),
          ],
          const SizedBox(height: AppUI.s12),
          for (final it in t.items) _itemLine(it),
          const SizedBox(height: AppUI.s12),
          AppButton(
            label: isNuevo ? 'Empezar a preparar' : 'Pedido listo 🛎️',
            variant:
                isNuevo ? AppButtonVariant.secondary : AppButtonVariant.primary,
            onPressed: () => _advance(t),
          ),
        ],
      ),
    );
  }

  Widget _itemLine(OrderItem it) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppUI.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Text('${it.quantity}×',
                    style: AppUI.tabularStrong),
              ),
              Expanded(
                child: Text(
                  '${it.emoji != null && it.emoji!.isNotEmpty ? '${it.emoji} ' : ''}${it.productName}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppUI.bodyStrong,
                ),
              ),
            ],
          ),
          if (it.notes != null)
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Text(
                '“${it.notes}”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFFB45309),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Pestaña Para entregar ─────────────────────────────────────────────────

  Widget _entregarTab() {
    final listos = _listos;
    if (listos.isEmpty) {
      return _emptyState(
        icon: Icons.room_service_rounded,
        title: 'Nada por entregar',
        subtitle:
            'Cuando la cocina marque un pedido como listo, aparecerá aquí.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppUI.s16),
        children: [
          for (final t in listos) _entregarCard(t),
          const SizedBox(height: AppUI.s24),
        ],
      ),
    );
  }

  Widget _entregarCard(OrderTicket t) {
    final waitMin = _minutesSince(t.listoAt ?? t.createdAt);
    final orphan = waitMin >= kOrphanAlertMinutes;
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s12),
      padding: const EdgeInsets.all(AppUI.s16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUI.radius),
        boxShadow: AppUI.shadow,
        border: Border(
          left: BorderSide(
              color: orphan ? AppTheme.error : AppTheme.success, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppUI.title),
              ),
              const SizedBox(width: AppUI.s8),
              MinimalBadge(
                label: orphan
                    ? '¡Listo hace $waitMin min!'
                    : 'Listo hace $waitMin min',
                color: orphan ? AppTheme.error : AppTheme.success,
              ),
            ],
          ),
          const SizedBox(height: AppUI.s4),
          Text(
            [
              if ((t.customerName ?? '').isNotEmpty) t.customerName!,
              '${t.itemCount} producto${t.itemCount == 1 ? '' : 's'}',
              if (t.isPrepaid) 'PAGADO' else 'Por cobrar ${formatCOP(t.total)}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppUI.bodySoft,
          ),
          const SizedBox(height: AppUI.s12),
          AppButton(
            label: _delivering.contains(t.uuid)
                ? 'Entregando…'
                : 'Confirmar ENTREGA',
            onPressed: _delivering.contains(t.uuid)
                ? null
                : () => _markDelivered(t),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 56, color: AppUI.inkSoft.withValues(alpha: 0.5)),
        const SizedBox(height: AppUI.s16),
        Text(title, textAlign: TextAlign.center, style: AppUI.title),
        const SizedBox(height: AppUI.s8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppUI.s24),
          child: Text(subtitle,
              textAlign: TextAlign.center, style: AppUI.bodySoft),
        ),
      ],
    );
  }

  static int _minutesSince(DateTime dt) =>
      DateTime.now().difference(dt).inMinutes;
}

class _PendingAdvance {
  final String uuid;
  final OrderStatus newStatus;
  final Timer timer;
  _PendingAdvance(
      {required this.uuid, required this.newStatus, required this.timer});
}
