import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tax_settings_service.dart';
import '../../theme/app_theme.dart';
import 'tax_activation_wizard.dart';

/// Owner-facing screen that exposes the VAT (IVA) configuration:
///   1. Show whether VAT is currently active and since when
///   2. If inactive — open the no-return activation wizard
///   3. If active — toggle Inclusive vs Exclusive in-place, change
///      the rate from a small set of presets, or soft-deactivate
///
/// The screen is a thin view over [TaxSettingsService]. We never store
/// duplicate state in the widget — the service is the single source of
/// truth and the screen rebuilds from a [ListenableBuilder].
class TaxSettingsScreen extends StatelessWidget {
  const TaxSettingsScreen({super.key});

  TaxSettingsService get _service => TaxSettingsService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: const Text(
          'Configuración de Impuestos',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary),
          tooltip: 'Volver',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final enabled = _service.enabled;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatusCard(
                  enabled: enabled,
                  activatedAt: _service.activatedAt,
                ),
                const SizedBox(height: 20),
                if (!enabled) _buildActivateCta(context),
                if (enabled) ..._buildActiveBlock(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActivateCta(BuildContext context) {
    return ElevatedButton.icon(
      key: const Key('btn_activate_iva_wizard'),
      onPressed: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TaxActivationWizard(),
          ),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
      icon: const Icon(Icons.rocket_launch_rounded),
      label: const Text('Activar IVA — Wizard guiado'),
    );
  }

  List<Widget> _buildActiveBlock(BuildContext context) {
    final inclusive = _service.inclusive;
    final rate = _service.rate;
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: SwitchListTile(
          key: const Key('switch_iva_inclusive'),
          value: inclusive,
          activeThumbColor: const Color(0xFF10B981),
          title: const Text(
            'El precio de mis productos ya incluye el IVA',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            inclusive
                ? 'El IVA se calcula desde el precio de venta'
                : 'Se suma el IVA al cobrar',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          onChanged: (v) {
            HapticFeedback.selectionClick();
            _service.setInclusive(v);
          },
        ),
      ),
      const SizedBox(height: 16),
      _RatePicker(
        currentRate: rate,
        onPick: (newRate) {
          HapticFeedback.selectionClick();
          _service.setRate(newRate);
        },
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        key: const Key('btn_deactivate_iva'),
        onPressed: () => _confirmDeactivate(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFDC2626),
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: Color(0xFFDC2626)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.power_settings_new_rounded),
        label: const Text('Desactivar IVA'),
      ),
    ];
  }

  Future<void> _confirmDeactivate(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Desactivar IVA?'),
        content: const Text(
          'Las ventas a partir de hoy NO llevarán IVA. Los recibos y '
          'reportes pasados se conservan tal cual — el IVA quedó '
          'congelado en cada venta cuando se cerró.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.deactivate();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('IVA desactivado para ventas futuras'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.enabled, required this.activatedAt});

  final bool enabled;
  final DateTime? activatedAt;

  String _fmt(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dotColor =
        enabled ? const Color(0xFF10B981) : const Color(0xFF9CA3AF);
    final bg = enabled
        ? const Color(0xFFD1FAE5)
        : const Color(0xFFF3F4F6);
    final border = enabled
        ? const Color(0xFF10B981)
        : const Color(0xFFD1D5DB);
    final text = enabled
        ? (activatedAt != null
            ? 'IVA Activo desde ${_fmt(activatedAt!)}'
            : 'IVA Activo')
        : 'IVA Inactivo';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatePicker extends StatelessWidget {
  const _RatePicker({required this.currentRate, required this.onPick});

  final double currentRate;
  final ValueChanged<double> onPick;

  static const _presets = <({String label, double value})>[
    (label: '0%', value: 0.0),
    (label: '5%', value: 0.05),
    (label: '19%', value: 0.19),
  ];

  @override
  Widget build(BuildContext context) {
    final isCustom = !_presets.any((p) => (p.value - currentRate).abs() < 1e-9);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tasa de IVA',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _presets)
                ChoiceChip(
                  key: Key('chip_iva_${p.label}'),
                  label: Text(p.label),
                  selected: !isCustom &&
                      (p.value - currentRate).abs() < 1e-9,
                  onSelected: (_) => onPick(p.value),
                ),
              ChoiceChip(
                key: const Key('chip_iva_custom'),
                label: Text(isCustom
                    ? '${(currentRate * 100).toStringAsFixed(1)}%'
                    : 'Personalizado'),
                selected: isCustom,
                onSelected: (_) => _promptCustom(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _promptCustom(BuildContext context) async {
    final ctrl = TextEditingController(
      text: (currentRate * 100).toStringAsFixed(1),
    );
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Tasa personalizada'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Porcentaje (0–50)',
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              if (raw == null) {
                Navigator.of(ctx).pop();
                return;
              }
              final clamped = raw.clamp(0.0, 50.0).toDouble();
              Navigator.of(ctx).pop(clamped / 100.0);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (picked != null) onPick(picked);
  }
}
