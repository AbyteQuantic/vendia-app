// Spec: specs/084-peluqueria-salon/spec.md (Fase 2 — agenda de citas/turnos)
//
// Agenda del salón: lista las citas reservadas (públicas + creadas) agrupadas
// por día, con su estado y acciones rápidas (confirmar / atendida / cancelar).
// Estética kit AppUI.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key, ApiService? apiOverride})
      : _apiOverride = apiOverride;
  final ApiService? _apiOverride;

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  late final ApiService _api =
      widget._apiOverride ?? ApiService(AuthService());

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _appts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.getAppointments();
      if (mounted) {
        setState(() {
          _appts = rows.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo cargar la agenda.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _setStatus(Map<String, dynamic> a, String status) async {
    HapticFeedback.lightImpact();
    try {
      await _api.updateAppointment(a['id'] as String, {'status': status});
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar la cita.')),
        );
      }
    }
  }

  // Mejora #1 — cobrar la cita (convertir en venta) eligiendo el medio de pago.
  Future<void> _convert(Map<String, dynamic> a) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppUI.s16),
              child: Text('¿Cómo pagó el cliente?', style: AppUI.bodyStrong),
            ),
            for (final m in const [
              ['cash', 'Efectivo'],
              ['transfer', 'Transferencia'],
              ['card', 'Tarjeta'],
            ])
              ListTile(
                title: Text(m[1]),
                onTap: () => Navigator.of(ctx).pop(m[0]),
              ),
          ],
        ),
      ),
    );
    if (method == null) return;
    try {
      await _api.convertAppointment(a['id'] as String, paymentMethod: method);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cobrado. La comisión quedó en Liquidaciones.')));
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo cobrar la cita.')));
      }
    }
  }

  // Mejora #3 — recordatorio por WhatsApp (deep link wa.me, sin API oficial).
  Future<void> _remind(Map<String, dynamic> a) async {
    HapticFeedback.lightImpact();
    final phoneRaw = (a['customer_phone'] as String?)?.replaceAll(RegExp(r'\D'), '');
    if (phoneRaw == null || phoneRaw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Esta cita no tiene celular.')));
      }
      return;
    }
    final phone = phoneRaw.length == 10 ? '57$phoneRaw' : phoneRaw;
    final dt = DateTime.tryParse(a['starts_at'] as String? ?? '')?.toLocal();
    final when = dt == null ? '' : ' el ${dt.day}/${dt.month} a las ${dt.toString().substring(11, 16)}';
    final svc = (a['service_name'] as String?) ?? 'su servicio';
    final msg = Uri.encodeComponent(
        'Hola ${(a['customer_name'] as String?) ?? ''}, le recordamos su turno '
        'para $svc$when. ¡Le esperamos!');
    final uri = Uri.parse('https://wa.me/$phone?text=$msg');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // Backlog #2 — marcar asistencia de hoy (para el arriendo de silla por días).
  Future<void> _openAttendance() async {
    HapticFeedback.lightImpact();
    List<Map<String, dynamic>> staff = const [];
    try {
      staff = await _api.fetchEmployees();
      staff = staff.where((e) => (e['is_active'] as bool?) ?? true).toList();
    } catch (_) {/* sin lista → sheet vacío */}
    if (!mounted) return;
    final marked = <String>{};
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppUI.s16),
            children: [
              const Text('Asistencia de hoy', style: AppUI.title),
              const SizedBox(height: 4),
              const Text(
                  'Marque los profesionales que asistieron hoy. El arriendo de '
                  'silla se cobra solo por los días presentes.',
                  style: AppUI.bodySoft),
              const SizedBox(height: AppUI.s12),
              if (staff.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppUI.s12),
                  child: Text('No hay profesionales activos.',
                      style: AppUI.bodySoft),
                ),
              for (final e in staff)
                Builder(builder: (_) {
                  final id = (e['uuid'] ?? e['id']) as String?;
                  final done = id != null && marked.contains(id);
                  return ListTile(
                    leading: Icon(
                      done ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: done ? const Color(0xFF10B981) : AppUI.inkSoft,
                    ),
                    title: Text((e['name'] as String?) ?? 'Profesional'),
                    onTap: done || id == null
                        ? null
                        : () async {
                            try {
                              await _api.markAttendance(id);
                              setSheet(() => marked.add(id));
                            } catch (_) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            'No se pudo marcar la asistencia.')));
                              }
                            }
                          },
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  /// Agrupa por día (yyyy-mm-dd) preservando el orden ascendente.
  Map<String, List<Map<String, dynamic>>> _byDay() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final a in _appts) {
      final iso = a['starts_at'] as String?;
      if (iso == null) continue;
      final dt = DateTime.tryParse(iso)?.toLocal();
      if (dt == null) continue;
      final key =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(a);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + AppUI.s8;
    final byDay = _byDay();
    final days = byDay.keys.toList()..sort();
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        title: 'Agenda de turnos',
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          IconButton(
            tooltip: 'Asistencia de hoy',
            icon: const Icon(Icons.how_to_reg_rounded),
            onPressed: _openAttendance,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(AppUI.s16, topPad, AppUI.s16, AppUI.s24),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: AppUI.s24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _InfoCard(text: _error!)
            else if (_appts.isEmpty)
              const _InfoCard(
                text:
                    'Aún no hay turnos reservados. Comparta su link de reservas '
                    'para que sus clientes aparten su turno en línea.',
              )
            else
              for (final day in days) ...[
                Padding(
                  padding: const EdgeInsets.only(
                      left: AppUI.s4, top: AppUI.s8, bottom: AppUI.s8),
                  child: Text(_dayLabel(day), style: AppUI.sectionLabel),
                ),
                ...byDay[day]!.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: AppUI.s12),
                      child: _ApptCard(
                        a: a,
                        onConfirm: () => _setStatus(a, 'confirmada'),
                        onConvert: () => _convert(a),
                        onRemind: () => _remind(a),
                        onCancel: () => _setStatus(a, 'cancelada'),
                      ),
                    )),
              ],
          ],
        ),
      ),
    );
  }

  String _dayLabel(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return key;
    const months = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    return '${d.day} de ${months[d.month - 1]}';
  }
}

String agendaStatusLabel(String? s) {
  switch (s) {
    case 'pendiente':
      return 'Pendiente';
    case 'confirmada':
      return 'Confirmada';
    case 'atendida':
      return 'Atendida';
    case 'cancelada':
      return 'Cancelada';
    case 'no_show':
      return 'No llegó';
    default:
      return s ?? '';
  }
}

Color agendaStatusColor(String? s) {
  switch (s) {
    case 'confirmada':
      return AppTheme.primary;
    case 'atendida':
      return const Color(0xFF10B981);
    case 'cancelada':
    case 'no_show':
      return Colors.redAccent;
    default:
      return AppUI.inkSoft;
  }
}

class _ApptCard extends StatelessWidget {
  const _ApptCard({
    required this.a,
    required this.onConfirm,
    required this.onConvert,
    required this.onRemind,
    required this.onCancel,
  });
  final Map<String, dynamic> a;
  final VoidCallback onConfirm;
  final VoidCallback onConvert;
  final VoidCallback onRemind;
  final VoidCallback onCancel;

  String _time() {
    final dt = DateTime.tryParse(a['starts_at'] as String? ?? '')?.toLocal();
    if (dt == null) return '';
    return dt.toLocal().toString().substring(11, 16);
  }

  @override
  Widget build(BuildContext context) {
    final status = a['status'] as String?;
    final svc = (a['service_name'] as String?)?.trim();
    final pro = (a['employee_name'] as String?)?.trim();
    final cliente = (a['customer_name'] as String?)?.trim();
    final phone = (a['customer_phone'] as String?)?.trim();
    final active = status != 'cancelada' && status != 'atendida';
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_time(),
                  style: AppUI.bodyStrong.copyWith(color: AppTheme.primary)),
              const SizedBox(width: AppUI.s12),
              Expanded(
                child: Text(svc?.isNotEmpty == true ? svc! : 'Servicio',
                    style: AppUI.bodyStrong),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: agendaStatusColor(status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppUI.radiusSm),
                ),
                child: Text(agendaStatusLabel(status),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: agendaStatusColor(status))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (pro?.isNotEmpty == true) pro,
              if (cliente?.isNotEmpty == true) cliente,
              if (phone?.isNotEmpty == true) phone,
            ].join(' · '),
            style: AppUI.bodySoft,
          ),
          if (active) ...[
            const SizedBox(height: AppUI.s12),
            Wrap(
              spacing: AppUI.s8,
              runSpacing: AppUI.s8,
              children: [
                if (status == 'pendiente')
                  _ActionChip(
                    label: 'Confirmar',
                    icon: Icons.check_rounded,
                    onTap: onConfirm,
                  ),
                _ActionChip(
                  label: 'Cobrar',
                  icon: Icons.point_of_sale_rounded,
                  onTap: onConvert,
                ),
                if (phone?.isNotEmpty == true)
                  _ActionChip(
                    label: 'Recordar',
                    icon: Icons.chat_rounded,
                    onTap: onRemind,
                  ),
                _ActionChip(
                  label: 'Cancelar',
                  icon: Icons.close_rounded,
                  danger: true,
                  onTap: onCancel,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : AppTheme.primary;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 36),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_note_rounded, color: AppTheme.primary),
          const SizedBox(width: AppUI.s12),
          Expanded(child: Text(text, style: AppUI.bodySoft)),
        ],
      ),
    );
  }
}
