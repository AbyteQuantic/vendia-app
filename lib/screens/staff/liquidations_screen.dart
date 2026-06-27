// Spec: specs/084-peluqueria-salon/spec.md
//
// Liquidaciones a profesionales (peluquería/barbería): lista por profesional con
// lo generado y su parte del periodo, detalle del desglose, y registro del pago
// (append-only). Incluye descargo legal permanente. Estética kit AppUI.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';

/// Formatea un monto COP entero: 12345 → "$12.345". Maneja negativos.
String formatCop(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${neg ? '-' : ''}\$${buf.toString()}';
}

const String kStaffLegalDisclaimer =
    'Información general, no asesoría legal. Esta guía y estos registros son solo '
    'informativos para organizar su negocio. No constituyen asesoría jurídica, '
    'laboral ni tributaria, ni garantizan el cumplimiento de ninguna norma. La '
    'clasificación de su relación con cada profesional (laboral, prestación de '
    'servicios o arrendamiento) depende de los hechos reales de su operación y la '
    'define, en últimas, la autoridad competente (primacía de la realidad). Antes '
    'de tomar decisiones sobre contratación, pagos, prestaciones o seguridad '
    'social, consulte a un profesional idóneo.';

class LiquidationsScreen extends StatefulWidget {
  const LiquidationsScreen({super.key, ApiService? apiOverride})
      : _apiOverride = apiOverride;

  final ApiService? _apiOverride;

  @override
  State<LiquidationsScreen> createState() => _LiquidationsScreenState();
}

class _LiquidationsScreenState extends State<LiquidationsScreen> {
  late final ApiService _api =
      widget._apiOverride ?? ApiService(AuthService());

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _until = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getLiquidation(
        from: _fmtDate(_from),
        until: _fmtDate(_until),
      );
      final rows = (data['rows'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo cargar la liquidación.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _until),
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _until = picked.end;
      });
      _load();
    }
  }

  void _openDetail(Map<String, dynamic> row) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _LiquidationDetailScreen(
        api: _api,
        row: row,
        from: _from,
        until: _until,
        onPaid: _load,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + AppUI.s8;
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        title: 'Liquidaciones',
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          IconButton(
            tooltip: 'Guía legal',
            icon: const Icon(Icons.gavel_rounded),
            onPressed: () => showStaffLegalGuide(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding:
              EdgeInsets.fromLTRB(AppUI.s16, topPad, AppUI.s16, AppUI.s24),
          children: [
            _RangeCard(
              label: '${_fmtDate(_from)} → ${_fmtDate(_until)}',
              onTap: _pickRange,
            ),
            const SizedBox(height: AppUI.s16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: AppUI.s24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _InfoCard(icon: Icons.error_outline_rounded, text: _error!)
            else if (_rows.isEmpty)
              const _InfoCard(
                icon: Icons.content_cut_rounded,
                text:
                    'Aún no hay servicios atribuidos a profesionales en este periodo. '
                    'Al cobrar, asigne el profesional que realizó cada servicio.',
              )
            else
              ..._rows.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: AppUI.s12),
                    child: _ProRow(row: r, onTap: () => _openDetail(r)),
                  )),
            const SizedBox(height: AppUI.s16),
            const _DisclaimerFooter(),
          ],
        ),
      ),
    );
  }
}

/// Texto del modelo de pago en español.
String payModelLabel(String? m) {
  switch (m) {
    case 'commission':
      return 'Comisión por servicio';
    case 'fixed_per_job':
      return 'Pago fijo por trabajo';
    case 'chair_rent':
      return 'Arriendo de silla';
    case 'salary_commission':
      return 'Sueldo + comisión';
    default:
      return 'Sin esquema definido';
  }
}

class _ProRow extends StatelessWidget {
  const _ProRow({required this.row, required this.onTap});
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (row['employee_name'] as String?)?.trim();
    final payout = (row['payout'] as Map<String, dynamic>?) ?? const {};
    final net = (payout['net_payout'] as num?) ?? 0;
    final count = (payout['service_count'] as num?)?.toInt() ?? 0;
    final toSalon = (payout['direction'] as String?) == 'to_salon';
    return GestureDetector(
      onTap: onTap,
      child: SoftCard(
        child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppUI.hairline,
            child: Icon(Icons.person_rounded, color: AppTheme.primary),
          ),
          const SizedBox(width: AppUI.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name?.isNotEmpty == true ? name! : 'Profesional',
                    style: AppUI.bodyStrong),
                const SizedBox(height: 2),
                Text('$count servicios · ${payModelLabel(row['pay_model'] as String?)}',
                    style: AppUI.bodySoft),
              ],
            ),
          ),
          const SizedBox(width: AppUI.s8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatCop(net),
                  style: AppUI.bodyStrong.copyWith(
                      color: net < 0 ? Colors.redAccent : AppTheme.primary)),
              Text(toSalon ? 'debe al salón' : 'a pagar',
                  style: AppUI.bodySoft),
            ],
          ),
        ],
        ),
      ),
    );
  }
}

class _RangeCard extends StatelessWidget {
  const _RangeCard({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SoftCard(
        child: Row(
          children: [
            const Icon(Icons.date_range_rounded, color: AppTheme.primary),
            const SizedBox(width: AppUI.s12),
            Expanded(child: Text('Periodo: $label', style: AppUI.bodyStrong)),
            const Icon(Icons.edit_calendar_outlined,
                color: AppUI.inkSoft, size: 20),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(width: AppUI.s12),
          Expanded(child: Text(text, style: AppUI.bodySoft)),
        ],
      ),
    );
  }
}

class _DisclaimerFooter extends StatelessWidget {
  const _DisclaimerFooter();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppUI.s4),
      child: Text(
        'Guía informativa, no asesoría legal. Cada caso depende de los hechos '
        'reales y lo define la autoridad competente. Consulte a un profesional.',
        style: AppUI.bodySoft.copyWith(fontSize: 11),
      ),
    );
  }
}

/// Muestra la guía legal completa en una hoja inferior.
void showStaffLegalGuide(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(AppUI.s24),
        children: [
          const Text('Guía legal y administrativa', style: AppUI.title),
          const SizedBox(height: AppUI.s16),
          ..._legalTips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: AppUI.s12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: AppUI.bodyStrong),
                    Expanded(child: Text(t, style: AppUI.bodySoft)),
                  ],
                ),
              )),
          const SizedBox(height: AppUI.s8),
          const Divider(),
          const SizedBox(height: AppUI.s8),
          Text(kStaffLegalDisclaimer, style: AppUI.bodySoft.copyWith(fontSize: 12)),
        ],
      ),
    ),
  );
}

const List<String> _legalTips = [
  'En Colombia, lo que define si hay relación laboral NO es cómo se le pague, '
      'sino los hechos reales: si hay subordinación, horario y exclusividad, '
      'podría existir contrato de trabajo (primacía de la realidad).',
  'Arriendo de silla: si el salón fija el precio, cobra por su caja, asigna '
      'horario o exige exclusividad, ese arriendo podría llegar a verse como '
      'relación laboral. Verifíquelo con un profesional.',
  'Si hay relación laboral, recuerde la afiliación a seguridad social (salud, '
      'pensión, ARL) y el reconocimiento de prestaciones.',
  'ARL: el oficio implica riesgos (químicos, navajas, tijeras). Considere la '
      'cobertura de riesgos laborales.',
  'Conserve los comprobantes de pago firmados o aceptados por el profesional, '
      'al menos 3 años.',
];

// ── Detalle + registrar pago ────────────────────────────────────────────────

class _LiquidationDetailScreen extends StatelessWidget {
  const _LiquidationDetailScreen({
    required this.api,
    required this.row,
    required this.from,
    required this.until,
    required this.onPaid,
  });

  final ApiService api;
  final Map<String, dynamic> row;
  final DateTime from;
  final DateTime until;
  final VoidCallback onPaid;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top + kToolbarHeight + AppUI.s8;
    final p = (row['payout'] as Map<String, dynamic>?) ?? const {};
    final name = (row['employee_name'] as String?)?.trim();
    final net = (p['net_payout'] as num?) ?? 0;
    final toSalon = (p['direction'] as String?) == 'to_salon';

    Widget line(String label, num? value, {bool strong = false}) {
      if (value == null || value == 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style: strong ? AppUI.bodyStrong : AppUI.bodySoft)),
            Text(formatCop(value),
                style: strong ? AppUI.bodyStrong : AppUI.bodySoft),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppUI.pageBg,
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        title: name?.isNotEmpty == true ? name! : 'Profesional',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(AppUI.s16, topPad, AppUI.s16, AppUI.s24),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payModelLabel(row['pay_model'] as String?),
                    style: AppUI.bodyStrong),
                const SizedBox(height: AppUI.s8),
                line('Servicios realizados',
                    (p['service_count'] as num?)?.toInt()),
                line('Total generado', p['gross_services'] as num?),
                line('Comisión', p['commission_amount'] as num?),
                line('Pago fijo', p['fixed_amount'] as num?),
                line('Sueldo base', p['salary_amount'] as num?),
                line('Arriendo de silla', p['chair_rent_amount'] as num?),
                line('Propina', p['tip_amount'] as num?),
                const Divider(),
                line(toSalon ? 'Debe al salón' : 'Total a pagar', net,
                    strong: true),
              ],
            ),
          ),
          const SizedBox(height: AppUI.s16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _registerPayment(context, name, net, toSalon),
              icon: const Icon(Icons.payments_outlined, size: 20),
              label: Text(toSalon ? 'Registrar cobro de arriendo' : 'Registrar pago'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
          const SizedBox(height: AppUI.s24),
          const _DisclaimerFooter(),
        ],
      ),
    );
  }

  Future<void> _registerPayment(
      BuildContext context, String? name, num net, bool toSalon) async {
    final method = ValueNotifier<String>('efectivo');
    final notesCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(AppUI.s24, AppUI.s24, AppUI.s24,
            MediaQuery.viewInsetsOf(ctx).bottom + AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(toSalon ? 'Cobrar arriendo' : 'Registrar pago a ${name ?? ''}',
                style: AppUI.title),
            const SizedBox(height: AppUI.s8),
            Text('Monto: ${formatCop(net.abs())}', style: AppUI.bodyStrong),
            const SizedBox(height: AppUI.s16),
            ValueListenableBuilder<String>(
              valueListenable: method,
              builder: (_, m, __) => Wrap(
                spacing: AppUI.s8,
                children: [
                  for (final opt in const ['efectivo', 'transferencia', 'otro'])
                    ChoiceChip(
                      label: Text(opt),
                      selected: m == opt,
                      onSelected: (_) => method.value = opt,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppUI.s12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppUI.s16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Confirmar'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    try {
      await api.createPayout({
        'employee_uuid': row['employee_uuid'],
        'employee_name': name ?? '',
        'kind': toSalon ? 'arriendo' : 'liquidacion',
        'direction': toSalon ? 'to_salon' : 'to_pro',
        'pay_model': row['pay_model'],
        'period_start': from.toUtc().toIso8601String(),
        'period_end': until.toUtc().toIso8601String(),
        'net_payout': net,
        'method': method.value,
        'notes': notesCtrl.text.trim(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pago registrado.')),
        );
        onPaid();
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo registrar el pago.')),
        );
      }
    }
  }
}
