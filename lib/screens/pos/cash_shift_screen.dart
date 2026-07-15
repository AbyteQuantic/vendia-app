// Spec: specs/105-hito-restaurante-comandas/spec.md — F5 (turno de caja).
//
// El control antirrobo del dueño ausente: abrir el turno declarando la
// base del cajón → vender normal (las ventas se atan solas) → cerrar
// contando → la app muestra esperado (base + efectivo) vs contado y la
// DIFERENCIA en grande. El historial (solo dueño/admin) queda abajo.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_ui.dart';
import '../../utils/format_cop.dart';
import '../../widgets/branch_selector_drawer.dart';

class CashShiftScreen extends StatefulWidget {
  final ApiService? apiOverride;
  const CashShiftScreen({super.key, this.apiOverride});

  @override
  State<CashShiftScreen> createState() => _CashShiftScreenState();
}

class _CashShiftScreenState extends State<CashShiftScreen> {
  late final ApiService _api;

  bool _loading = true;
  bool _failed = false;
  Map<String, dynamic>? _current; // {shift, cash_sales, running_expected}
  List<Map<String, dynamic>> _history = [];
  bool _busy = false;

  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api = widget.apiOverride ?? ApiService(AuthService());
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final current = await _api.fetchCurrentCashShift();
      List<Map<String, dynamic>> history = [];
      try {
        history = await _api.fetchCashShifts();
      } catch (_) {
        // 403 para roles de piso: el historial es del dueño. La vista
        // de turno actual sigue funcionando.
      }
      if (!mounted) return;
      setState(() {
        _current = current;
        _history = history;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  double? _parseAmount(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (clean.isEmpty) return null;
    return double.tryParse(clean);
  }

  Future<void> _open() async {
    final amount = _parseAmount(_amountCtrl.text);
    if (amount == null) {
      _snack('Ingrese la base del cajón (puede ser 0).', error: true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      await _api.openCashShift(openingAmount: amount);
      _amountCtrl.clear();
      await _load();
      _snack('Turno abierto con base ${formatCOP(amount)}');
    } catch (_) {
      _snack('No se pudo abrir el turno. Revise la conexión.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    final shift = (_current?['shift'] as Map?)?.cast<String, dynamic>();
    if (shift == null) return;
    final counted = _parseAmount(_amountCtrl.text);
    if (counted == null) {
      _snack('Cuente el cajón e ingrese el total.', error: true);
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final closed = await _api.closeCashShift(
        shift['id'] as String,
        countedAmount: counted,
        notes: _notesCtrl.text.trim(),
      );
      _amountCtrl.clear();
      _notesCtrl.clear();
      await _load();
      if (!mounted) return;
      _showClosedSummary(closed);
    } catch (_) {
      _snack('No se pudo cerrar el turno. Revise la conexión.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showClosedSummary(Map<String, dynamic> shift) {
    final expected = (shift['expected_amount'] as num?)?.toDouble() ?? 0;
    final counted = (shift['counted_amount'] as num?)?.toDouble() ?? 0;
    final diff = (shift['difference'] as num?)?.toDouble() ?? 0;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppUI.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              diff == 0
                  ? '✅ Caja cuadrada'
                  : diff > 0
                      ? 'Sobran ${formatCOP(diff)}'
                      : 'Faltan ${formatCOP(-diff)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: diff == 0
                    ? AppTheme.success
                    : (diff > 0 ? AppTheme.warning : AppTheme.error),
              ),
            ),
            const SizedBox(height: AppUI.s16),
            _kv('Esperado (base + efectivo)', formatCOP(expected)),
            _kv('Contado', formatCOP(counted)),
            const SizedBox(height: AppUI.s16),
            AppButton(
                label: 'Entendido',
                onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppUI.s4),
        child: Row(
          children: [
            Expanded(child: Text(k, style: AppUI.bodySoft)),
            Text(v, style: AppUI.tabularStrong),
          ],
        ),
      );

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppUI.pageBg,
      appBar: glassAppBar(
        title: 'Turno de Caja',
        onBack: () => Navigator.of(context).pop(),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppUI.s8),
            child: Center(child: BranchSelectorChip()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? _errorState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppUI.s16),
                    children: [
                      _current == null ? _openCard() : _currentCard(),
                      if (_history.isNotEmpty) ...[
                        const SizedBox(height: AppUI.s24),
                        const Text('TURNOS ANTERIORES',
                            style: AppUI.sectionLabel),
                        const SizedBox(height: AppUI.s8),
                        for (final h in _history.where((h) =>
                            h['status'] == 'closed')) _historyTile(h),
                      ],
                      const SizedBox(height: AppUI.s24),
                    ],
                  ),
                ),
    );
  }

  Widget _errorState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No se pudo cargar el turno.', style: AppUI.bodyStrong),
            const SizedBox(height: AppUI.s12),
            AppButton(
                label: 'Reintentar',
                expand: false,
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _failed = false;
                  });
                  _load();
                }),
          ],
        ),
      );

  Widget _openCard() {
    return SoftCard(
      padding: const EdgeInsets.all(AppUI.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Abrir turno', style: AppUI.title),
          const SizedBox(height: AppUI.s4),
          const Text(
            'Cuente el sencillo del cajón y declárelo como base.',
            style: AppUI.bodySoft,
          ),
          const SizedBox(height: AppUI.s12),
          TextField(
            key: const Key('shift_amount_field'),
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Base del cajón',
              prefixText: r'$ ',
            ),
          ),
          const SizedBox(height: AppUI.s16),
          AppButton(
            label: _busy ? 'Abriendo…' : 'Abrir turno',
            onPressed: _busy ? null : _open,
          ),
        ],
      ),
    );
  }

  Widget _currentCard() {
    final shift = (_current!['shift'] as Map).cast<String, dynamic>();
    final cash = (_current!['cash_sales'] as num?)?.toDouble() ?? 0;
    final expected =
        (_current!['running_expected'] as num?)?.toDouble() ?? 0;
    final salesCount = (_current!['sales_count'] as num?)?.toInt() ?? 0;
    final base = (shift['opening_amount'] as num?)?.toDouble() ?? 0;
    final openedBy = (shift['opened_by_name'] as String?) ?? '';

    return SoftCard(
      padding: const EdgeInsets.all(AppUI.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: Text('Turno abierto', style: AppUI.title)),
              MinimalBadge(label: 'EN CURSO', color: AppTheme.success),
            ],
          ),
          if (openedBy.isNotEmpty) ...[
            const SizedBox(height: AppUI.s4),
            Text('Abrió: $openedBy',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppUI.bodySoft),
          ],
          const SizedBox(height: AppUI.s12),
          _kv('Base declarada', formatCOP(base)),
          _kv('Ventas en efectivo ($salesCount ventas)', formatCOP(cash)),
          const Divider(height: AppUI.s16, color: AppUI.hairline),
          _kv('Debe haber en el cajón', formatCOP(expected)),
          const SizedBox(height: AppUI.s16),
          TextField(
            key: const Key('shift_amount_field'),
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Conteo del cajón (para cerrar)',
              prefixText: r'$ ',
            ),
          ),
          const SizedBox(height: AppUI.s8),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
            ),
          ),
          const SizedBox(height: AppUI.s16),
          AppButton(
            label: _busy ? 'Cerrando…' : 'Cerrar turno y cuadrar',
            variant: AppButtonVariant.danger,
            onPressed: _busy ? null : _close,
          ),
        ],
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> h) {
    final diff = (h['difference'] as num?)?.toDouble() ?? 0;
    final openedAt =
        DateTime.tryParse((h['opened_at'] as String?) ?? '')?.toLocal();
    final label = openedAt == null
        ? 'Turno'
        : '${openedAt.day}/${openedAt.month} ${openedAt.hour.toString().padLeft(2, '0')}:${openedAt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: AppUI.s8),
      padding: const EdgeInsets.all(AppUI.s12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppUI.radius),
        boxShadow: AppUI.shadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppUI.bodyStrong),
                Text(
                  '${(h['opened_by_name'] as String?)?.isNotEmpty == true ? h['opened_by_name'] : 'Sin nombre'} · esperado ${formatCOP((h['expected_amount'] as num?)?.toDouble() ?? 0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppUI.bodySoft,
                ),
              ],
            ),
          ),
          MinimalBadge(
            label: diff == 0
                ? 'Cuadrada'
                : (diff > 0
                    ? '+${formatCOP(diff)}'
                    : '−${formatCOP(-diff)}'),
            color: diff == 0
                ? AppTheme.success
                : (diff > 0 ? AppTheme.warning : AppTheme.error),
          ),
        ],
      ),
    );
  }
}
