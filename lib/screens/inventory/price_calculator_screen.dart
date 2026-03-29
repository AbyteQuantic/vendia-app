import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../utils/format_cop.dart';

/// Calculadora de Ganancia — sets a sale price with custom numpad
/// and dynamic profit indicator.
class PriceCalculatorScreen extends StatefulWidget {
  final String productName;
  final String productEmoji;
  final double costPrice;

  const PriceCalculatorScreen({
    super.key,
    required this.productName,
    required this.productEmoji,
    required this.costPrice,
  });

  @override
  State<PriceCalculatorScreen> createState() => _PriceCalculatorScreenState();
}

class _PriceCalculatorScreenState extends State<PriceCalculatorScreen> {
  String _priceInput = '';

  /// Suggests a sale price with 25% margin, rounded up to nearest $50.
  double get _suggestedPrice {
    final suggested = widget.costPrice * 1.25;
    return (suggested / 50).ceil() * 50;
  }

  double get _currentPrice {
    if (_priceInput.isEmpty) return 0;
    return double.tryParse(_priceInput) ?? 0;
  }

  double get _profit => _currentPrice - widget.costPrice;

  double get _profitPercent {
    if (widget.costPrice <= 0) return 0;
    return (_profit / widget.costPrice) * 100;
  }

  String get _profitLabel {
    if (_currentPrice <= 0) return '';
    if (_profit <= 0) return 'Sin ganancia';
    final pct = _profitPercent.round();
    if (pct >= 20) {
      return 'Excelente. Ganancia: ${formatCOP(_profit)} ($pct%)';
    } else if (pct >= 10) {
      return 'Buena. Ganancia: ${formatCOP(_profit)} ($pct%)';
    } else {
      return 'Baja. Ganancia: ${formatCOP(_profit)} ($pct%)';
    }
  }

  void _onDigit(String digit) {
    HapticFeedback.lightImpact();
    setState(() {
      _priceInput += digit;
    });
  }

  void _onBackspace() {
    HapticFeedback.lightImpact();
    if (_priceInput.isNotEmpty) {
      setState(() {
        _priceInput = _priceInput.substring(0, _priceInput.length - 1);
      });
    }
  }

  void _confirmPrice(double price) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(price);
  }

  @override
  Widget build(BuildContext context) {
    final suggestedProfit = _suggestedPrice - widget.costPrice;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Volver',
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 28),
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Poner Precio',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      body: Semantics(
        label: 'Calculadora de precio de venta',
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGrey,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.borderColor, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0x20667EEA),
                                    Color(0x20764BA2),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  widget.productEmoji,
                                  style: const TextStyle(fontSize: 32),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.productName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Costo: ${formatCOP(widget.costPrice)}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Suggested price card
                      Semantics(
                        button: true,
                        label:
                            'Precio sugerido: ${formatCOP(_suggestedPrice)}',
                        child: GestureDetector(
                          onTap: () => _confirmPrice(_suggestedPrice),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0x1010B981),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFF10B981),
                                  width: 2),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Precio sugerido',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Vender a ${formatCOP(_suggestedPrice)}',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Le gana ${formatCOP(suggestedProfit)} por unidad',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Custom price input
                      const Text(
                        'O escriba su precio:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Price display field
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 18),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGrey,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFF667EEA), width: 2.5),
                        ),
                        child: Text(
                          _priceInput.isEmpty
                              ? '\$ 0'
                              : '\$ ${_formatInput(_priceInput)}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Dynamic profit indicator
                      if (_currentPrice > 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: _profit > 0
                                ? const Color(0x1510B981)
                                : const Color(0x15DC2626),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            _profit > 0
                                ? '\uD83D\uDCB0 $_profitLabel'
                                : '\u26A0\uFE0F $_profitLabel',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _profit > 0
                                  ? const Color(0xFF10B981)
                                  : AppTheme.error,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Custom numpad
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppTheme.background,
                child: Column(
                  children: [
                    // Numpad grid: 4 rows x 3 cols
                    _buildNumpadRow(['1', '2', '3']),
                    const SizedBox(height: 8),
                    _buildNumpadRow(['4', '5', '6']),
                    const SizedBox(height: 8),
                    _buildNumpadRow(['7', '8', '9']),
                    const SizedBox(height: 8),
                    _buildNumpadRow(['00', '0', 'backspace']),

                    const SizedBox(height: 12),

                    // Confirm button
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF10B981),
                              Color(0xFF059669),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _currentPrice > 0
                              ? () => _confirmPrice(_currentPrice)
                              : null,
                          icon: const Icon(Icons.check_rounded,
                              size: 24, color: Colors.white),
                          label: const Text(
                            'Confirmar Precio',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            disabledBackgroundColor: Colors.transparent,
                            disabledForegroundColor:
                                Colors.white.withValues(alpha: 0.5),
                            minimumSize: const Size(double.infinity, 64),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumpadRow(List<String> keys) {
    return Row(
      children: keys
          .map((key) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _NumpadButton(
                    label: key,
                    onTap: () {
                      if (key == 'backspace') {
                        _onBackspace();
                      } else {
                        _onDigit(key);
                      }
                    },
                  ),
                ),
              ))
          .toList(),
    );
  }

  String _formatInput(String input) {
    // Format with dots for thousands
    final number = int.tryParse(input);
    if (number == null) return input;
    return formatCOP(number.toDouble()).replaceFirst('\$', '');
  }
}

class _NumpadButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NumpadButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isBackspace = label == 'backspace';

    return Semantics(
      button: true,
      label: isBackspace ? 'Borrar' : label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: isBackspace
                ? const Color(0x15DC2626)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: isBackspace
                ? const Icon(Icons.backspace_rounded,
                    color: AppTheme.error, size: 28)
                : Text(
                    label,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
