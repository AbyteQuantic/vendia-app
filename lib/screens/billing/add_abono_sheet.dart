import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/format_cop.dart';

class AddAbonoSheet extends StatefulWidget {
  final double saldoPendiente;
  final ValueChanged<double> onConfirm;

  const AddAbonoSheet({
    super.key,
    required this.saldoPendiente,
    required this.onConfirm,
  });

  @override
  State<AddAbonoSheet> createState() => _AddAbonoSheetState();
}

class _AddAbonoSheetState extends State<AddAbonoSheet> {
  String _amountStr = '';

  double get _amount => double.tryParse(_amountStr) ?? 0;

  bool get _isValid => _amount > 0 && _amount <= widget.saldoPendiente;

  void _onDigit(String digit) {
    HapticFeedback.lightImpact();
    setState(() {
      _amountStr += digit;
    });
  }

  void _onBackspace() {
    HapticFeedback.lightImpact();
    if (_amountStr.isNotEmpty) {
      setState(() {
        _amountStr = _amountStr.substring(0, _amountStr.length - 1);
      });
    }
  }

  void _onClear() {
    HapticFeedback.lightImpact();
    setState(() {
      _amountStr = '';
    });
  }

  void _onConfirmNumpad() {
    if (!_isValid) return;
    HapticFeedback.mediumImpact();
    widget.onConfirm(_amount);
    Navigator.pop(context);
  }

  void _setQuickAmount(double value) {
    HapticFeedback.lightImpact();
    setState(() {
      _amountStr = value.toInt().toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Registrar abono. Saldo pendiente: ${formatCOP(widget.saldoPendiente)}',
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDragHandle(),
              const SizedBox(height: 16),
              _buildTitle(),
              const SizedBox(height: 12),
              _buildSaldoBadge(),
              const SizedBox(height: 16),
              _buildAmountDisplay(),
              const SizedBox(height: 16),
              _buildQuickAmountButtons(),
              const SizedBox(height: 16),
              _buildNumpad(),
              const SizedBox(height: 16),
              _buildConfirmButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Semantics(
      header: true,
      child: const Text(
        'Registrar Abono',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  Widget _buildSaldoBadge() {
    return Semantics(
      label: 'Saldo pendiente: ${formatCOP(widget.saldoPendiente)}',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Saldo pendiente: ${formatCOP(widget.saldoPendiente)}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFFDC2626),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountDisplay() {
    final displayText = _amount > 0 ? formatCOP(_amount) : '\$0';
    return Semantics(
      label: 'Monto ingresado: $displayText',
      liveRegion: true,
      child: Text(
        displayText,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: Color(0xFF667EEA),
        ),
      ),
    );
  }

  Widget _buildQuickAmountButtons() {
    final quickAmounts = <MapEntry<String, double>>[
      const MapEntry('\$5.000', 5000),
      const MapEntry('\$10.000', 10000),
      const MapEntry('\$20.000', 20000),
      MapEntry('Todo', widget.saldoPendiente),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: quickAmounts.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              button: true,
              label: entry.key == 'Todo'
                  ? 'Abonar todo: ${formatCOP(widget.saldoPendiente)}'
                  : 'Abonar ${entry.key}',
              child: GestureDetector(
                onTap: () => _setQuickAmount(entry.value),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF764BA2)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF764BA2),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNumpad() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
        const spacing = 8.0;
        const totalSpacing = spacing * (columns - 1);
        final buttonSize =
            ((constraints.maxWidth - totalSpacing) / columns).clamp(64.0, 90.0);

        return Column(
          children: [
            _numpadRow(['1', '2', '3', '⌫'], buttonSize, spacing),
            const SizedBox(height: spacing),
            _numpadRow(['4', '5', '6', '00'], buttonSize, spacing),
            const SizedBox(height: spacing),
            _numpadRow(['7', '8', '9', '000'], buttonSize, spacing),
            const SizedBox(height: spacing),
            _numpadRow(['C', '0', '.', '✓'], buttonSize, spacing),
          ],
        );
      },
    );
  }

  Widget _numpadRow(List<String> keys, double buttonSize, double spacing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.asMap().entries.map((entry) {
        final index = entry.key;
        final key = entry.value;
        return Padding(
          padding: EdgeInsets.only(left: index > 0 ? spacing : 0),
          child: _numpadButton(key, buttonSize),
        );
      }).toList(),
    );
  }

  Widget _numpadButton(String key, double size) {
    Color bgColor;
    Widget child;
    VoidCallback? onTap;

    switch (key) {
      case '⌫':
        bgColor = Colors.grey.shade200;
        child = Icon(Icons.backspace_rounded, size: 24, color: Colors.grey.shade700);
        onTap = _onBackspace;
        break;
      case 'C':
        bgColor = Colors.white;
        child = const Text(
          'C',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFFDC2626),
          ),
        );
        onTap = _onClear;
        break;
      case '✓':
        bgColor = const Color(0xFF10B981);
        child = const Icon(Icons.check_rounded, size: 28, color: Colors.white);
        onTap = _isValid ? _onConfirmNumpad : null;
        break;
      case '.':
        // COP doesn't use decimals, but keep the button for layout consistency
        bgColor = Colors.white;
        child = const Text(
          '.',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF374151),
          ),
        );
        onTap = () {
          // No-op for COP (no decimals)
          HapticFeedback.lightImpact();
        };
        break;
      default:
        bgColor = Colors.white;
        child = Text(
          key,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF374151),
          ),
        );
        onTap = () => _onDigit(key);
    }

    final semanticLabel = switch (key) {
      '⌫' => 'Borrar',
      'C' => 'Limpiar todo',
      '✓' => 'Confirmar monto',
      '.' => 'Punto decimal',
      _ => key,
    };

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size.clamp(64.0, 72.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    final label = 'CONFIRMAR ABONO ${_amount > 0 ? formatCOP(_amount) : ''}';

    return Semantics(
      button: true,
      enabled: _isValid,
      label: _isValid
          ? 'Confirmar abono de ${formatCOP(_amount)}'
          : 'Ingrese un monto valido para confirmar',
      child: GestureDetector(
        onTap: _isValid
            ? () {
                HapticFeedback.mediumImpact();
                widget.onConfirm(_amount);
                Navigator.pop(context);
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: _isValid
                ? const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  )
                : null,
            color: _isValid ? null : Colors.grey.shade300,
          ),
          alignment: Alignment.center,
          child: Text(
            label.trim(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _isValid ? Colors.white : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}
