// Spec: specs/042-modulo-eventos/spec.md
//
// Mapa de sillas del evento (F042). Pantalla del organizador para asignar,
// mover o liberar la silla de cada asistente sobre un mapa gráfico limpio:
//   - sillas asignadas vs libres diferenciadas por color,
//   - buscador por nombre de asistente o número de silla,
//   - tocar una silla libre → elegir asistente (con buscador) para asignar,
//   - tocar una silla asignada → liberar o reasignar.
// La auto-asignación en el primer abono la hace el backend; este mapa permite
// el ajuste manual. Gerontodiseño: objetivos táctiles grandes, 360dp.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/event.dart';
import '../../services/api_service.dart';
import '../../services/app_error.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

const Color _seatAccent = Color(0xFF1A2FA0);

class EventSeatMapSheet extends StatefulWidget {
  final String eventId;
  final int capacity;
  final List<EventRegistrationView> registrations;
  final ApiService? apiOverride;

  const EventSeatMapSheet({
    super.key,
    required this.eventId,
    required this.capacity,
    required this.registrations,
    this.apiOverride,
  });

  @override
  State<EventSeatMapSheet> createState() => _EventSeatMapSheetState();
}

class _EventSeatMapSheetState extends State<EventSeatMapSheet> {
  late final ApiService _api;
  late List<EventRegistrationView> _regs;
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _busy = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _regs = List.of(widget.registrations);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Total de sillas a pintar: el cupo si está definido, o el correlativo más
  /// alto asignado / número de inscritos cuando es "sin límite".
  int get _seatCount {
    if (widget.capacity > 0) return widget.capacity;
    final maxAssigned = _regs
        .map((r) => r.seatNumber ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    return [maxAssigned, _regs.length, 1].reduce((a, b) => a > b ? a : b);
  }

  EventRegistrationView? _occupant(int seat) {
    for (final r in _regs) {
      if (r.seatNumber == seat) return r;
    }
    return null;
  }

  List<EventRegistrationView> get _unassigned =>
      _regs.where((r) => r.seatNumber == null).toList();

  bool _matchesQuery(int seat, EventRegistrationView? occ) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (seat.toString() == q) return true;
    if (occ != null && occ.customerName.toLowerCase().contains(q)) return true;
    return false;
  }

  Future<void> _assign(EventRegistrationView reg, int? seat) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated =
          await _api.assignEventSeat(widget.eventId, reg.id, seat);
      final newSeat = (updated['seat_number'] as num?)?.toInt();
      setState(() {
        _regs = _regs
            .map((r) => r.id == reg.id ? r.copyWithSeat(newSeat) : r)
            .toList();
        _changed = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_friendly(e), style: const TextStyle(fontSize: 16)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    final s = e is AppError ? e.message : e.toString();
    return s.replaceFirst('Exception: ', '');
  }

  // Tocar una silla LIBRE → elegir a quién asignar (asistentes sin silla).
  Future<void> _onTapFree(int seat) async {
    HapticFeedback.lightImpact();
    final pending = _unassigned;
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Todos los inscritos ya tienen silla.',
            style: TextStyle(fontSize: 16)),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final picked = await _pickAttendee(
        title: 'Asignar la silla $seat a…', options: pending);
    if (picked != null) await _assign(picked, seat);
  }

  // Tocar una silla ASIGNADA → liberar o reasignar.
  Future<void> _onTapTaken(int seat, EventRegistrationView occ) async {
    HapticFeedback.lightImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Silla $seat · ${occ.customerName}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded,
                  color: _seatAccent, size: 26),
              title: const Text('Mover a otra silla',
                  style: TextStyle(fontSize: 17)),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.event_seat_outlined,
                  color: AppTheme.error, size: 26),
              title: const Text('Liberar esta silla',
                  style: TextStyle(fontSize: 17)),
              onTap: () => Navigator.pop(ctx, 'free'),
            ),
          ],
        ),
      ),
    );
    if (action == 'free') {
      await _assign(occ, null);
    } else if (action == 'move') {
      final target = await _pickFreeSeat(exclude: seat);
      if (target != null) await _assign(occ, target);
    }
  }

  Future<EventRegistrationView?> _pickAttendee({
    required String title,
    required List<EventRegistrationView> options,
  }) {
    return showModalBottomSheet<EventRegistrationView>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final search = TextEditingController();
        var q = '';
        return StatefulBuilder(builder: (ctx, setSheet) {
          final filtered = options
              .where((r) =>
                  q.isEmpty || r.customerName.toLowerCase().contains(q))
              .toList();
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      style: const TextStyle(fontSize: 17),
                      decoration: const InputDecoration(
                        hintText: 'Buscar asistente por nombre',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setSheet(() => q = v.toLowerCase()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in filtered)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  _seatAccent.withValues(alpha: 0.12),
                              child: Text(
                                r.customerName.isNotEmpty
                                    ? r.customerName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(color: _seatAccent),
                              ),
                            ),
                            title: Text(r.customerName,
                                style: const TextStyle(fontSize: 17)),
                            subtitle: r.customerPhone.isEmpty
                                ? null
                                : Text(r.customerPhone),
                            onTap: () => Navigator.pop(ctx, r),
                          ),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Sin resultados',
                                style: TextStyle(fontSize: 16)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Future<int?> _pickFreeSeat({int? exclude}) {
    final free = <int>[
      for (var s = 1; s <= _seatCount; s++)
        if (_occupant(s) == null && s != exclude) s,
    ];
    if (free.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay sillas libres.', style: TextStyle(fontSize: 16)),
        behavior: SnackBarBehavior.floating,
      ));
      return Future.value(null);
    }
    return showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Elegir silla libre',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: GridView.count(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (final s in free)
                    InkWell(
                      onTap: () => Navigator.pop(ctx, s),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: _seatAccent, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$s',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _seatAccent)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final assigned = _regs.where((r) => r.seatNumber != null).length;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          title: const Text('Mapa de sillas',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(child: BranchSelectorChip()),
            )
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 17),
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre o número de silla',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              // Leyenda + contador.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: Row(
                  children: [
                    _legend(_seatAccent, 'Asignada'),
                    const SizedBox(width: 16),
                    _legend(Colors.grey.shade300, 'Libre'),
                    const Spacer(),
                    Text('$assigned/$_seatCount asignadas',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade700)),
                  ],
                ),
              ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: GridView.count(
                  padding: const EdgeInsets.all(16),
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                  children: [
                    for (var seat = 1; seat <= _seatCount; seat++)
                      _seatTile(seat),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(Color c, String label) => Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
        ],
      );

  Widget _seatTile(int seat) {
    final occ = _occupant(seat);
    final taken = occ != null;
    final matched = _matchesQuery(seat, occ);
    final dim = _query.trim().isNotEmpty && !matched;

    return Opacity(
      opacity: dim ? 0.3 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy
            ? null
            : () => taken ? _onTapTaken(seat, occ) : _onTapFree(seat),
        child: Container(
          decoration: BoxDecoration(
            color: taken ? _seatAccent : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: matched && _query.trim().isNotEmpty
                  ? AppTheme.success
                  : (taken ? _seatAccent : Colors.grey.shade300),
              width: matched && _query.trim().isNotEmpty ? 2.5 : 1.2,
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.event_seat_rounded,
                  size: 26,
                  color: taken ? Colors.white : Colors.grey.shade400),
              const SizedBox(height: 2),
              Text('$seat',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: taken ? Colors.white : AppTheme.textPrimary)),
              if (taken)
                Text(
                  occ.customerName.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
