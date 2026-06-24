import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tax_settings_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/branch_selector_drawer.dart';

/// Three-step Stepper wizard the owner walks through the FIRST time
/// VAT (IVA) is enabled. Three reasons for the wizard rather than a
/// single switch:
///   • Clear no-return messaging — once enabled, future sales freeze
///     VAT bytes onto every line. Switching off later does NOT
///     retroactively erase that math.
///   • Force the rate decision up-front so we never default to 19%
///     for a non-tax-registered tienda.
///   • Force the Inclusive vs Exclusive decision up-front since it
///     materially changes the price the customer pays.
class TaxActivationWizard extends StatefulWidget {
  const TaxActivationWizard({super.key});

  @override
  State<TaxActivationWizard> createState() => _TaxActivationWizardState();
}

class _TaxActivationWizardState extends State<TaxActivationWizard> {
  int _currentStep = 0;
  bool _accepted = false;
  double _rate = 0.19;
  bool _customRate = false;
  final TextEditingController _customRateCtrl =
      TextEditingController(text: '19');
  bool _inclusive = true;
  bool _busy = false;

  @override
  void dispose() {
    _customRateCtrl.dispose();
    super.dispose();
  }

  bool get _canStepOneContinue => _accepted;

  bool get _canStepTwoContinue {
    if (_customRate) {
      final raw = double.tryParse(_customRateCtrl.text.trim().replaceAll(',', '.'));
      if (raw == null) return false;
      return raw >= 0 && raw <= 50;
    }
    return true;
  }

  /// Resolved rate at the moment we activate. We don't persist to the
  /// state during typing — keeping the source of truth on the input
  /// avoids weird flips when the user toggles between presets.
  double _effectiveRate() {
    if (!_customRate) return _rate;
    final raw = double.tryParse(_customRateCtrl.text.trim().replaceAll(',', '.'));
    if (raw == null) return _rate;
    return (raw.clamp(0.0, 50.0) / 100.0).toDouble();
  }

  Future<void> _activate() async {
    setState(() => _busy = true);
    try {
      await TaxSettingsService.instance.activate(
        rate: _effectiveRate(),
        inclusive: _inclusive,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('IVA activado correctamente'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF10B981),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: const Text(
          'Activar IVA',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: BranchSelectorChip()),
          )
        ],
      ),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: _onContinue,
        onStepCancel: _onCancel,
        controlsBuilder: _buildControls,
        steps: [
          Step(
            isActive: _currentStep >= 0,
            title: const Text('Términos'),
            content: _buildStepTerms(),
          ),
          Step(
            isActive: _currentStep >= 1,
            title: const Text('Tasa de IVA'),
            content: _buildStepRate(),
          ),
          Step(
            isActive: _currentStep >= 2,
            title: const Text('Modalidad de cobro'),
            content: _buildStepMode(),
          ),
        ],
      ),
    );
  }

  void _onContinue() {
    if (_currentStep == 0 && !_canStepOneContinue) return;
    if (_currentStep == 1 && !_canStepTwoContinue) return;
    if (_currentStep < 2) {
      setState(() => _currentStep += 1);
    } else {
      _activate();
    }
  }

  void _onCancel() {
    if (_currentStep == 0) {
      Navigator.of(context).pop();
    } else {
      setState(() => _currentStep -= 1);
    }
  }

  Widget _buildControls(BuildContext context, ControlsDetails details) {
    final isLast = _currentStep == 2;
    final canContinue = switch (_currentStep) {
      0 => _canStepOneContinue,
      1 => _canStepTwoContinue,
      _ => true,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          ElevatedButton(
            key: Key('btn_wizard_continue_$_currentStep'),
            onPressed: canContinue && !_busy ? details.onStepContinue : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(isLast ? 'Activar IVA' : 'Siguiente'),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: _busy ? null : details.onStepCancel,
            child: Text(_currentStep == 0 ? 'Cancelar' : 'Atrás'),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTerms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Activar el IVA es una decisión de no-retorno fiscal:',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '• Las ventas a partir de hoy llevarán IVA congelado en cada '
          'línea.\n'
          '• Los recibos pasados quedan intactos — el IVA no se '
          'recalcula hacia atrás.\n'
          '• Apagar el IVA mañana NO altera lo que ya cerró hoy.',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          key: const Key('check_wizard_accept'),
          value: _accepted,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _accepted = v ?? false);
          },
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Entiendo y acepto'),
        ),
      ],
    );
  }

  Widget _buildStepRate() {
    // Sentinel value used to represent the "custom" option in the unified
    // RadioGroup<double>. Any negative number works because rates are >= 0.
    const double customSentinel = -1;
    return RadioGroup<double>(
      groupValue: _customRate ? customSentinel : _rate,
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          if (v == customSentinel) {
            _customRate = true;
          } else {
            _customRate = false;
            _rate = v;
          }
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RadioListTile<double>(
            key: Key('radio_rate_0'),
            value: 0,
            title: Text('0%'),
            subtitle: Text('Productos exentos / no responsable'),
          ),
          const RadioListTile<double>(
            key: Key('radio_rate_5'),
            value: 0.05,
            title: Text('5%'),
            subtitle: Text('Tarifa reducida'),
          ),
          const RadioListTile<double>(
            key: Key('radio_rate_19'),
            value: 0.19,
            title: Text('19%'),
            subtitle: Text('Tarifa general (Colombia)'),
          ),
          RadioListTile<double>(
            key: const Key('radio_rate_custom'),
            value: customSentinel,
            title: const Text('Personalizado'),
            subtitle: TextField(
              key: const Key('field_rate_custom'),
              controller: _customRateCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: _customRate,
              decoration: const InputDecoration(
                labelText: 'Tasa (0 – 50)',
                suffixText: '%',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepMode() {
    final rate = _effectiveRate();
    // Live preview anchored at $10.000 so the difference between the
    // two modalities is unambiguous to a non-accountant owner.
    const exampleNet = 10000.0;
    final inclusiveTax = exampleNet - exampleNet / (1 + rate);
    final exclusiveTax = exampleNet * rate;
    const inclusiveCustomerPays = exampleNet;
    final exclusiveCustomerPays = exampleNet + exclusiveTax;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: SwitchListTile(
            key: const Key('switch_wizard_inclusive'),
            value: _inclusive,
            activeThumbColor: const Color(0xFF10B981),
            title: const Text(
              'El precio ya incluye IVA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            subtitle: Text(
              _inclusive
                  ? 'Inclusive: el cliente paga exactamente el precio publicado.'
                  : 'Exclusive: se suma el IVA encima del precio publicado.',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _inclusive = v);
            },
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Ejemplo en vivo (producto a \$10.000)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        _ExampleRow(
          label: 'Inclusive',
          customerPays: inclusiveCustomerPays,
          ivaAmount: inclusiveTax,
          rate: rate,
          highlighted: _inclusive,
        ),
        const SizedBox(height: 8),
        _ExampleRow(
          label: 'Exclusive',
          customerPays: exclusiveCustomerPays,
          ivaAmount: exclusiveTax,
          rate: rate,
          highlighted: !_inclusive,
        ),
      ],
    );
  }
}

class _ExampleRow extends StatelessWidget {
  const _ExampleRow({
    required this.label,
    required this.customerPays,
    required this.ivaAmount,
    required this.rate,
    required this.highlighted,
  });

  final String label;
  final double customerPays;
  final double ivaAmount;
  final double rate;
  final bool highlighted;

  String _money(double v) {
    final cents = v.round();
    final s = cents.abs().toString();
    final buf = StringBuffer(cents < 0 ? '-\$' : '\$');
    final start = s.length % 3;
    if (start > 0) buf.write(s.substring(0, start));
    for (int i = start; i < s.length; i += 3) {
      if (i > 0) buf.write('.');
      buf.write(s.substring(i, i + 3));
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFD1FAE5) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted
              ? const Color(0xFF10B981)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'IVA (${(rate * 100).toStringAsFixed(0)}%): ${_money(ivaAmount)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Cliente paga ${_money(customerPays)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
