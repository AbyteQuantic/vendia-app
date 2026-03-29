import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';

/// NewOrderScreen — Mesero selecciona mesa o turno antes de tomar el pedido.
/// Amber color scheme (#F59E0B -> #D97706) distinguishes waiter flow from POS.
class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key});

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  String _label = '';
  bool _isParaLlevar = false;

  // ── Amber palette ──
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberDark = Color(0xFFD97706);

  String get _displayLabel {
    if (_isParaLlevar) return 'Para llevar';
    if (_label.isEmpty) return '';
    return 'Mesa $_label';
  }

  String get _buttonText {
    if (_isParaLlevar) return 'Iniciar Pedido Para llevar';
    if (_label.isEmpty) return 'Escriba mesa o nombre';
    return 'Iniciar Pedido Mesa $_label';
  }

  bool get _canProceed => _label.isNotEmpty || _isParaLlevar;

  void _selectQuickChip(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == 'Para llevar') {
        _isParaLlevar = true;
        _label = '';
      } else {
        _isParaLlevar = false;
        _label = value.replaceAll('Mesa ', '');
      }
    });
  }

  void _tapNumpad(int number) {
    HapticFeedback.lightImpact();
    setState(() {
      _isParaLlevar = false;
      if (_label.length < 3) {
        _label += number.toString();
      }
    });
  }

  void _clearInput() {
    HapticFeedback.lightImpact();
    setState(() {
      _label = '';
      _isParaLlevar = false;
    });
  }

  void _startOrder() {
    if (!_canProceed) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _PlaceholderWaiterPOS(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header with amber gradient ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_amber, _amberDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Semantics(
                        button: true,
                        label: 'Volver',
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.arrow_back_rounded,
                                color: Colors.white, size: 28),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nuevo Pedido',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '\u00bfPara d\u00f3nde es este pedido?',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Question text ──
            const Text(
              'Escriba el n\u00famero de mesa o nombre',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: AppTheme.textSecondary,
              ),
            ),

            const SizedBox(height: 20),

            // ── Large display input ──
            Center(
              child: GestureDetector(
                onTap: _clearInput,
                child: Container(
                  width: 200,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGrey,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _canProceed ? _amber : AppTheme.borderColor,
                      width: 3,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _displayLabel.isNotEmpty ? _displayLabel : '...',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _canProceed
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Quick chips ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _QuickChip(
                    label: 'Mesa 1',
                    isSelected: !_isParaLlevar && _label == '1',
                    onTap: () => _selectQuickChip('Mesa 1'),
                  ),
                  const SizedBox(width: 12),
                  _QuickChip(
                    label: 'Mesa 2',
                    isSelected: !_isParaLlevar && _label == '2',
                    onTap: () => _selectQuickChip('Mesa 2'),
                  ),
                  const SizedBox(width: 12),
                  _QuickChip(
                    label: 'Para llevar',
                    isSelected: _isParaLlevar,
                    onTap: () => _selectQuickChip('Para llevar'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Mini numpad (1-3) ──
            SizedBox(
              width: 280,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (int n = 1; n <= 3; n++)
                    _NumpadButton(
                      number: n,
                      onTap: () => _tapNumpad(n),
                    ),
                ],
              ),
            ),

            const Spacer(),

            // ── Bottom action button ──
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Semantics(
                button: true,
                label: _buttonText,
                child: GestureDetector(
                  onTap: _canProceed ? _startOrder : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: _canProceed
                          ? const LinearGradient(
                              colors: [_amber, _amberDark],
                            )
                          : null,
                      color: _canProceed ? null : AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: _canProceed
                          ? [
                              BoxShadow(
                                color: _amber.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.restaurant_rounded,
                          color:
                              _canProceed ? Colors.white : AppTheme.textSecondary,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _buttonText,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _canProceed
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Quick chip button ──────────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  static const Color _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: isSelected ? _amber : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: _amber,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : _amber,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Numpad button ──────────────────────────────────────────────────────────────

class _NumpadButton extends StatelessWidget {
  final int number;
  final VoidCallback onTap;

  const _NumpadButton({required this.number, required this.onTap});

  static const Color _amber = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'N\u00famero $number',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.surfaceGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _amber, width: 2),
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// Temporary placeholder — will be replaced by WaiterPosScreen
class _PlaceholderWaiterPOS extends StatelessWidget {
  const _PlaceholderWaiterPOS();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pedido')),
      body: const Center(child: Text('WaiterPosScreen placeholder')),
    );
  }
}
